import 'dart:io';

import '../speed/speed_prober.dart';
import 'latency_prober.dart';

/// 延迟优选（流程对齐原 Python 项目 cfnb，排名改为综合质量分）：
/// 1. 对所有节点做并发「裸 TCP 建连」延迟测试（网络层真实 RTT，不受 TLS/SNI 影响）。
/// 2. 对【所有 TCP 连通节点】用 speed.cloudflare.com 作 SNI 直连测真实带宽（每节点
///    [speedProbes] 次取中位数去抖），任何能回数据的节点都测得出真实吞吐；裸协议节点失败→null。
/// 3. 最终排名按**综合质量分**降序取前 [topN] 名：quality = wLat·延迟分 + wSpeed·带宽分，
///    其中 wLat = [qualityLatencyWeight]（默认 0.3，带宽主导），wSpeed = 1 − wLat。
///    因为节点已是别人优选过的、延迟普遍低且差异小，故带宽权重更高以拉开区分度，
///    延迟仅用于惩罚异常高的节点。输出带名次（#1 = 综合质量最高）。
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
    int speedCap = 1000,
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

    // 带宽测速作用在所有【TCP 连通】节点上（对齐原项目：不过滤 latencyMaxMs，
    // 而是对所有连通节点测速——延迟 200~390ms 的 CF 节点同样能测出真实带宽）。
    // 所有节点统一用 speed.cloudflare.com 作 SNI 直连测真实吞吐；真正非 CF 的裸协议节点
    // 握手失败 → 带宽 null（这些节点靠延迟兜底排名）。
    Map<String, double?> speedMap = {};
    if (speedEnabled && connectedResults.isNotEmpty) {
      final bwNodes = (connectedResults.length <= speedCap
              ? connectedResults
              : connectedResults.take(speedCap))
          .map((r) => r.node)
          .toList();
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

    // 综合质量分（用于展示 Q 值）：延迟权重 + 带宽权重。
    final speedWeight = (1.0 - qualityLatencyWeight).clamp(0.0, 1.0);
    double quality(LatencyResult r) {
      final latScore = ((latencyMaxMs - r.latencyMs!) / latencyMaxMs).clamp(0.0, 1.0);
      final bw = speedMap[r.node];
      final bwScore = bw == null ? 0.0 : (bw / bandwidthRefMbps).clamp(0.0, 1.0);
      return qualityLatencyWeight * latScore + speedWeight * bwScore;
    }

    // 最终排名：综合「延迟 + 带宽」质量分降序取前 topN（带宽主导、延迟兜底）。
    // 这些节点已是别人优选过的，延迟普遍偏低、差异小，故带宽权重更高以拉开区分度；
    // 延迟项仅用于惩罚延迟异常高的节点。无速度的节点带宽分=0，靠延迟兜底排名。
    final sorted = connectedResults.toList()
      ..sort((a, b) => quality(b).compareTo(quality(a)));
    final keptResults = topN > 0 && topN < sorted.length
        ? sorted.take(topN).toList()
        : sorted;

    final keptCount = keptResults.length;
    final ts = DateTime.now().toString().substring(0, 19);
    final out = File(outputFile);
    await out.create(recursive: true);
    final sb = StringBuffer();
    sb.writeln('# 延迟优选结果 @ $ts | 共测 $tested 连通 $connected 保留前 $keptCount 名(按综合质量: 延迟${qualityLatencyWeight.toStringAsFixed(1)} 带宽${(1-qualityLatencyWeight).toStringAsFixed(1)})');
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
