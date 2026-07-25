import 'dart:convert';
import 'dart:io';

import '../net/ip.dart';
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
    Future<(double?, double?, int)> Function(String ip, int port, Duration timeout, {int probes})? probe,
    void Function(String)? onLog,
    bool Function()? isCancelled,
    void Function(int done, int total, int connected)? onProgress,
  }) async {
    final (ordered, tested, connected) = await latencyProbeAll(
      nodes,
      timeout: timeout,
      workers: workers,
      probes: probes,
      minSuccessRate: minSuccessRate,
      nodeSource: nodeSource,
      probe: probe,
      onLog: onLog,
      isCancelled: isCancelled,
      onProgress: onProgress,
    );

    final connectedResults = ordered.where((r) => r.latencyMs != null).toList();

    // 仅保留延迟 ≤ latencyMaxMs 的节点（0/负表示不限）。
    final capped = latencyMaxMs > 0
        ? connectedResults.where((r) => r.latencyMs! <= latencyMaxMs).toList()
        : connectedResults;

    // 加权综合评分：延迟 + 抖动，越低越好。
    // Score = latency + jitter * 0.5（抖动权重 50%）
    // 多次探测取最小值时抖动小的节点更稳定，应排名更前。
    final sorted = capped.toList()
      ..sort((a, b) {
        final sa = a.latencyMs! + (a.jitterMs ?? 0) * 0.5;
        final sb = b.latencyMs! + (b.jitterMs ?? 0) * 0.5;
        return sa.compareTo(sb);
      });
    final keptResults = topN > 0 && topN < sorted.length
        ? sorted.take(topN).toList()
        : sorted;

    final ts = DateTime.now().toString().substring(0, 19);
    final out = File(outputFile);
    await out.create(recursive: true);
    final sb = StringBuffer();
    // 纯数据输出：ip:port#国家名@来源 延迟
    for (var i = 0; i < keptResults.length; i++) {
      final r = keptResults[i];
      final lat = (r.latencyMs != null) ? '${r.latencyMs!.toStringAsFixed(2)}ms' : '超时';
      final displayNode = _displayNode(r.node);
      sb.writeln('$displayNode $lat');
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
        'jitter_ms': r.jitterMs == null ? null : (r.jitterMs! * 1000).round() / 1000,
      });
    }

    final sourceStats = <String, int>{};
    for (final rec in records) {
      final s = (rec['source'] as String).isEmpty ? '未知' : (rec['source'] as String);
      sourceStats[s] = (sourceStats[s] ?? 0) + 1;
    }

    final jsonFile = File('${out.path}.json');
    await jsonFile.writeAsString(jsonEncode({
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

  /// 将节点字符串中的国家码替换为中文名。
  /// 兼容新旧格式：
  ///   新: `1.2.3.4:443#HK CM` → `1.2.3.4:443#香港 CM`
  ///   旧: `1.2.3.4:443#HK@CM` → `1.2.3.4:443#香港@CM`
  static String _displayNode(String node) {
    final hashIdx = node.indexOf('#');
    if (hashIdx < 0) return node;
    final before = node.substring(0, hashIdx);
    final after = node.substring(hashIdx + 1);
    // 先找空格（新格式）或 @（旧格式）作为分隔
    final spaceIdx = after.indexOf(' ');
    final atIdx = after.indexOf('@');
    // 取第一个出现的分隔符位置
    int sepIdx = -1;
    if (spaceIdx >= 0 && (atIdx < 0 || spaceIdx < atIdx)) {
      sepIdx = spaceIdx;
    } else if (atIdx >= 0) {
      sepIdx = atIdx;
    }
    if (sepIdx >= 0) {
      final cc = after.substring(0, sepIdx);
      final rest = after.substring(sepIdx); // 保留分隔符
      return '$before#${countryCodeToName(cc)}$rest';
    }
    return '$before#${countryCodeToName(after)}';
  }
}

