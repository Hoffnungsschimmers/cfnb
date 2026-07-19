import 'dart:io';

import 'latency_prober.dart';

/// 延迟优选（纯「裸 TCP 建连」延迟测试，对齐代理软件 urltest 语义）：
/// 1. 对所有节点做并发「裸 TCP 建连」延迟测试（网络层真实 RTT，不受 TLS/SNI 影响）。
/// 2. 按延迟升序排名，仅保留延迟 ≤ [latencyMaxMs] 的节点（该上限为 0/负表示不限）。
/// 3. 取前 [topN] 名（0/负表示全部保留）。输出带名次（#1 = 延迟最低）。
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
    int topN = 200,
    Map<String, String>? nodeSource,
    String? sni,
    Future<(double?, int)> Function(String ip, int port, Duration timeout, {int probes, String? sni})? probe,
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

    // 仅保留延迟 ≤ latencyMaxMs 的节点（0/负表示不限）。
    final capped = latencyMaxMs > 0
        ? connectedResults.where((r) => r.latencyMs! <= latencyMaxMs).toList()
        : connectedResults;

    // 最终排名：延迟升序（越低越好）。
    final sorted = capped.toList()
      ..sort((a, b) => a.latencyMs!.compareTo(b.latencyMs!));
    final keptResults = topN > 0 && topN < sorted.length
        ? sorted.take(topN).toList()
        : sorted;

    final keptCount = keptResults.length;
    final ts = DateTime.now().toString().substring(0, 19);
    final out = File(outputFile);
    await out.create(recursive: true);
    final sb = StringBuffer();
    sb.writeln('# 延迟优选结果 @ $ts | 共测 $tested 连通 $connected 达标 ${capped.length} 保留前 $keptCount 名(按延迟升序)');
    for (var i = 0; i < keptResults.length; i++) {
      final r = keptResults[i];
      final rank = i + 1;
      final src = (nodeSource != null && nodeSource.containsKey(r.node))
          ? '@${nodeSource[r.node]}'
          : '';
      final lat = (r.latencyMs != null) ? ' ${r.latencyMs!.toStringAsFixed(2)}ms' : ' 超时';
      sb.writeln('${r.node}$src$lat #$rank');
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
      });
    }

    final sourceStats = <String, int>{};
    for (final rec in records) {
      final s = (rec['source'] as String).isEmpty ? '未知' : (rec['source'] as String);
      sourceStats[s] = (sourceStats[s] ?? 0) + 1;
    }

    final jsonFile = File('${out.path}.json');
    await jsonFile.writeAsString(_jsonEncode({
      'generated_at': ts,
      'tested': tested,
      'connected': connected,
      'passed': capped.length,
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
