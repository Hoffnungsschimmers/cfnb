import 'dart:async';
import 'dart:io';

/// 解析 `IP:端口#CC[@来源]` 节点行，返回 (ip, port)。
/// 支持 IPv4 与 [IPv6]:port 形式。无法解析返回 null。
(IpPort, int)? parseEndpoint(String node) {
  final base = node.split('#').first.trim();
  if (base.isEmpty) return null;

  String ip;
  String portStr;
  if (base.startsWith('[')) {
    final rb = base.indexOf(']');
    if (rb == -1) return null;
    ip = base.substring(1, rb);
    final rest = base.substring(rb + 1);
    if (!rest.startsWith(':')) return null;
    portStr = rest.substring(1);
  } else {
    final idx = base.lastIndexOf(':');
    if (idx < 0) return null;
    ip = base.substring(0, idx);
    portStr = base.substring(idx + 1);
  }
  final port = int.tryParse(portStr.trim());
  if (port == null || port <= 0 || port > 65535) return null;
  return (ip, port);
}

typedef IpPort = String;

/// 测量到 (ip, port) 的 TCP 连接延迟（毫秒）。失败/超时返回 null。
Future<double?> measureLatency(String ip, int port, Duration timeout) async {
  final sw = Stopwatch()..start();
  try {
    final sock = await Socket.connect(ip, port, timeout: timeout);
    await sock.close();
    return sw.elapsedMilliseconds.toDouble();
  } on SocketException {
    return null;
  } on TimeoutException {
    return null;
  }
}

/// 提取节点注释里的国家码（# 之后、@来源 之前）。
String nodeCountry(String node) {
  final comment = node.contains('#') ? node.split('#')[1] : '';
  return comment.split('@').first.trim();
}

/// 提取来源名（#CC@来源 中的来源部分）。
String nodeSource(String node) {
  if (!node.contains('#')) return '';
  final comment = node.split('#')[1];
  final at = comment.indexOf('@');
  return at >= 0 ? comment.substring(at + 1).trim() : '';
}

/// 延迟测试结果。
class LatencyResult {
  final String node;
  final double? latencyMs;
  LatencyResult(this.node, this.latencyMs);
}

/// 对节点列表做并发 TCP 延迟测试。
///
/// [nodeSource] 可选：节点 -> 来源名 映射，用于输出标注。
/// 返回全部结果（成功在前按延迟升序，失败在后），以及测试/连通计数。
Future<(List<LatencyResult>, int tested, int connected)> latencyProbeAll(
  List<String> nodes, {
  required Duration timeout,
  required int workers,
  Map<String, String>? nodeSource,
  Future<double?> Function(String ip, int port, Duration timeout)? probe,
}) async {
  final targets = <(String, IpPort, int)>[];
  for (final node in nodes) {
    final ep = parseEndpoint(node);
    if (ep != null) targets.add((node, ep.$1, ep.$2));
  }

  final results = <LatencyResult>[];
  final semaphore = _Semaphore(workers);
  await Future.wait(targets.map((t) async {
    await semaphore.acquire();
    try {
      final lat = await (probe ?? measureLatency)(t.$2, t.$3, timeout);
      results.add(LatencyResult(t.$1, lat));
    } finally {
      semaphore.release();
    }
  }));

  final succeeded = results.where((r) => r.latencyMs != null).toList()
    ..sort((a, b) => a.latencyMs!.compareTo(b.latencyMs!));
  final failed = results.where((r) => r.latencyMs == null).toList();
  final ordered = [...succeeded, ...failed];

  return (ordered, targets.length, succeeded.length);
}

/// 简易信号量，限制并发连接数。
class _Semaphore {
  int _count;
  final _queue = <Completer<void>>[];
  _Semaphore(this._count);

  Future<void> acquire() async {
    if (_count > 0) {
      _count--;
      return;
    }
    final c = Completer<void>();
    _queue.add(c);
    return c.future;
  }

  void release() {
    if (_queue.isNotEmpty) {
      _queue.removeAt(0).complete();
    } else {
      _count++;
    }
  }
}
