import 'dart:io';

import 'latency_prober.dart';

/// 延迟优选：对节点做并发延迟测试，按延迟排序保留前 topn，写主输出 + 结构化 JSON。
class LatencyFilter {
  /// 运行完整流程。返回 (保留节点列表, 测试数, 连通数)。
  static Future<(List<String>, int, int)> run({
    required List<String> nodes,
    required String outputFile,
    required int topN,
    required Duration timeout,
    required int workers,
    Map<String, String>? nodeSource,
    Future<double?> Function(String ip, int port, Duration timeout)? probe,
  }) async {
    final (ordered, tested, connected) = await latencyProbeAll(
      nodes,
      timeout: timeout,
      workers: workers,
      nodeSource: nodeSource,
      probe: probe,
    );

    final keptCount = topN < ordered.length ? topN : ordered.length;
    final kept = ordered.take(keptCount).map((r) => r.node).toList();

    final ts = DateTime.now().toString().substring(0, 19);
    final out = File(outputFile);
    await out.create(recursive: true);
    final sb = StringBuffer();
    sb.writeln('# 延迟优选结果 @ $ts | 共测 $tested 连通 $connected 保留 $keptCount');
    for (final r in ordered.take(keptCount)) {
      final src = (nodeSource != null && nodeSource.containsKey(r.node))
          ? '@${nodeSource[r.node]}'
          : '';
      if (r.latencyMs == null) {
        sb.writeln('${r.node}$src 超时');
      } else {
        sb.writeln('${r.node}$src ${r.latencyMs!.toStringAsFixed(2)} ms');
      }
    }
    await out.writeAsString(sb.toString());

    // 结构化 JSON
    final records = ordered.take(keptCount).map((r) {
      final ep = parseEndpoint(r.node);
      return {
        'ip': ep?.$1 ?? '',
        'port': ep?.$2 ?? 0,
        'country': nodeCountry(r.node),
        'source': nodeSource != null ? (nodeSource[r.node] ?? '') : '',
        'latency_ms': r.latencyMs == null ? null : (r.latencyMs! * 1000).round() / 1000,
      };
    }).toList();

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

    return (kept, tested, connected);
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
