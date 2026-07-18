import 'dart:io';

import '../speed/speed_prober.dart';
import 'latency_prober.dart';

/// 延迟优选：对节点做并发「TCP + TLS 握手」延迟测试（应用层真实延迟），
/// 保留「延迟 ≤ [latencyMaxMs]」的节点，再对【全部入围节点】测真实带宽（每节点 [speedProbes]
/// 次取中位数去抖），最后按**综合质量分**降序排序，保留质量最好的前 [topN] 名并写主输出 + JSON：
///   quality = wLat·(1 − latency/cutoff) + wSpeed·min(speed/refMbps, 1)
/// 其中 wLat = [qualityLatencyWeight]，wSpeed = 1 − wLat；[bandwidthRefMbps] 为带宽归一参考值
/// （直连节点常见 5~300Mbps，默认 30Mbps 让真实带宽差异拉开分数）。带宽测速作用在所有入围节点上，
/// 而非先截断前 N，确保「从所有好节点里挑真正最快的」。输出带名次（#1 最优），质量最高的 IP 排最前。
class LatencyFilter {
  /// 运行完整流程。返回 (保留节点列表, 测试数, 连通数)。
  static Future<(List<String>, int, int)> run({
    required List<String> nodes,
    required String outputFile,
    required int latencyMaxMs,
    required Duration timeout,
    required int workers,
    int probes = 1,
    double minSuccessRate = 1.0,
    bool speedEnabled = false,
    int speedLatencyLimitMs = 200,
    Duration? speedTimeout,
    int speedBytes = 1 * 1024 * 1024,
    int speedWorkers = 20,
    int speedProbes = 1,
    int speedCap = 300,
    int topN = 200,
    double qualityLatencyWeight = 0.6,
    double bandwidthRefMbps = 30.0,
    Map<String, String>? nodeSource,
    String? sni,
    Future<(double?, int)> Function(String ip, int port, Duration timeout, {int probes, String? sni})? probe,
    Future<double?> Function(String ip, int port, Duration timeout, {int bytes})? speedProbe,
    void Function(String)? onLog,
  }) async {
    final (ordered, tested, connected) = await latencyProbeAll(
      nodes,
      timeout: timeout,
      workers: workers,
      probes: probes,
      minSuccessRate: minSuccessRate,
      nodeSource: nodeSource,
      sni: sni,
      probe: probe,
      onLog: onLog,
    );

    final connectedResults = ordered.where((r) => r.latencyMs != null).toList();
    // 入围门槛：仅保留延迟 ≤ latencyMaxMs 的节点（连通性 + 应用层延迟合格）。
    final withinMax = connectedResults
        .where((r) => r.latencyMs! <= latencyMaxMs)
        .toList();

    // 带宽测速作用在【全部入围节点】上，而非先截断前 N——
    // 否则带宽无法参与「从所有好节点里挑真正快的」排序。
    Map<String, double?> speedMap = {};
    if (speedEnabled && withinMax.isNotEmpty) {
      final good = withinMax
          .where((r) => r.latencyMs! <= speedLatencyLimitMs)
          .toList();
      final pool = good.isNotEmpty ? good : withinMax;
      final bwNodes = pool.take(speedCap < pool.length ? speedCap : pool.length).map((r) => r.node).toList();
      speedMap = await measureBandwidthAll(
        bwNodes,
        timeout: speedTimeout ?? const Duration(seconds: 15),
        bytes: speedBytes,
        workers: speedWorkers,
        probes: speedProbes,
        onLog: onLog,
      );
      if (onLog != null) {
        final ok = speedMap.values.where((v) => v != null).length;
        onLog('带宽测速：候选 ${bwNodes.length}，测得速度 $ok');
      }
    }

    // 综合质量分：延迟权重 + 带宽权重（带宽权重 = 1 - 延迟权重）。
    // 延迟归一为 1 - latency/cutoff（0ms→1.0，截止→0）；带宽归一为 min(speed/ref,1)。
    final speedWeight = (1.0 - qualityLatencyWeight).clamp(0.0, 1.0);
    double quality(LatencyResult r) {
      final latScore = ((latencyMaxMs - r.latencyMs!) / latencyMaxMs).clamp(0.0, 1.0);
      final bw = speedMap[r.node];
      final bwScore = bw == null ? 0.0 : (bw / bandwidthRefMbps).clamp(0.0, 1.0);
      return qualityLatencyWeight * latScore + speedWeight * bwScore;
    }

    // 按综合质量分降序排序后，取前 topN 名（质量最优）。
    final sorted = withinMax.toList()
      ..sort((a, b) => quality(b).compareTo(quality(a)));
    final keptResults = topN > 0 && topN < sorted.length
        ? sorted.take(topN).toList()
        : sorted;

    final keptCount = keptResults.length;
    final ts = DateTime.now().toString().substring(0, 19);
    final out = File(outputFile);
    await out.create(recursive: true);
    final sb = StringBuffer();
    sb.writeln('# 延迟优选结果 @ $ts | 共测 $tested 连通 $connected 保留前 $keptCount 名(按质量)');
    for (var i = 0; i < keptResults.length; i++) {
      final r = keptResults[i];
      final rank = i + 1;
      final src = (nodeSource != null && nodeSource.containsKey(r.node))
          ? '@${nodeSource[r.node]}'
          : '';
      final spd = (speedMap[r.node] != null) ? ' ${speedMap[r.node]!.toStringAsFixed(2)}Mbps' : '';
      final lat = (r.latencyMs != null) ? ' ${r.latencyMs!.toStringAsFixed(2)}ms' : ' 超时';
      final q = quality(r);
      sb.writeln('${r.node}$src$lat$spd Q${q.toStringAsFixed(2)} #$rank');
    }
    await out.writeAsString(sb.toString());

    // 结构化 JSON
    final records = <Map<String, Object?>>[];
    for (var i = 0; i < keptResults.length; i++) {
      final r = keptResults[i];
      final ep = parseEndpoint(r.node);
      records.add({
        'rank': i + 1,
        'ip': ep?.$1 ?? '',
        'port': ep?.$2 ?? 0,
        'country': nodeCountry(r.node),
        'source': nodeSource != null ? (nodeSource[r.node] ?? '') : '',
        'latency_ms': r.latencyMs == null ? null : (r.latencyMs! * 1000).round() / 1000,
        'speed_mbps': speedMap[r.node],
        'quality': (quality(r) * 1000).round() / 1000,
      });
    }

    final sourceStats = <String, int>{};
    for (final rec in records) {
      final s = (rec['source'] as String).isEmpty ? '未知' : (rec['source'] as String);
      sourceStats[s] = (sourceStats[s] ?? 0) + 1;
    }

    final jsonPath = out.parent.path == '.' ? '${out.path}.json' : '${out.path}.json';
    final jsonFile = File(jsonPath);
    await jsonFile.writeAsString(_jsonEncode({
      'generated_at': ts,
      'tested': tested,
      'connected': connected,
      'kept': records.length,
      'source_stats': sourceStats,
      'nodes': records,
    }));

    return (keptResults.map((r) => r.node).toList(), tested, connected);
  }

  static String _jsonEncode(Object obj) {
    // 简易 JSON 序列化，避免引入 codec 依赖
    return _encodeValue(obj);
  }
}

String _encodeValue(Object? v) {
  if (v == null) return 'null';
  if (v is String) return '"${v.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';
  if (v is num) return v.toString();
  if (v is bool) return v.toString();
  if (v is List) return '[${v.map(_encodeValue).join(',')}]';
  if (v is Map) {
    final entries = v.entries.map((e) => '${_encodeValue(e.key)}:${_encodeValue(e.value)}');
    return '{${entries.join(',')}}';
  }
  return '"$v"';
}
