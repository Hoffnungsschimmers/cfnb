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

/// 测量到 (ip, port) 的 TCP 连接延迟（毫秒）。
///
/// 对应旧版 tester.py 的 test_tcp_latency_async：串行 [probes] 次连接，
/// 取**最小**成功延迟，并返回成功次数（用于后续成功率阈值过滤）。
/// 一次都没成功时返回 (null, 0)。
Future<(double?, int)> measureLatency(
  String ip,
  int port,
  Duration timeout, {
  String? sni,
  int probes = 1,
}) async {
  double? minLatency;
  var success = 0;
  for (var i = 0; i < probes; i++) {
    final sw = Stopwatch()..start();
    try {
      final sock = await Socket.connect(ip, port, timeout: timeout);
      await sock.close();
      final lat = sw.elapsedMilliseconds.toDouble();
      if (minLatency == null || lat < minLatency) minLatency = lat;
      success++;
    } on SocketException {
      // 本次失败，继续
    } on TimeoutException {
      // 本次超时，继续
    }
  }
  return (minLatency, success);
}

/// 测量到 (ip, port) 的「TCP 建连 + TLS 握手」延迟（毫秒）。
///
/// 对应 edgetunnel/vless 这类 WebSocket-over-TLS 代理的真实建连成本：
/// 客户端每次建链都要先 TCP 三次握手、再 TLS 握手（SNI = [sni]）。
/// 纯 TCP RTT 会漏掉 TLS 这层开销，本函数补上它，
/// 得到**最接近代理软件实际使用**的连接延迟。
/// 一次握手成功即返回耗时；超时/握手失败返回 (null, 0)。
Future<(double?, int)> measureTlsLatency(
  String ip,
  int port,
  Duration timeout, {
  String? sni,
  int probes = 1,
}) async {
  double? minLatency;
  var success = 0;
  for (var i = 0; i < probes; i++) {
    final sw = Stopwatch()..start();
    Socket? raw;
    try {
      raw = await Socket.connect(ip, port, timeout: timeout);
      final ctx = SecurityContext(withTrustedRoots: false);
      final ssl = await SecureSocket.secure(
        raw,
        host: sni ?? ip,
        context: ctx,
        onBadCertificate: (_) => true,
      );
      await ssl.close();
      final lat = sw.elapsedMilliseconds.toDouble();
      if (minLatency == null || lat < minLatency) minLatency = lat;
      success++;
    } on SocketException {
      // 本次失败，继续
    } on TimeoutException {
      // 本次超时，继续
    } on TlsException {
      // TLS 握手失败（节点不支持/证书异常），视为不可用
    } finally {
      try {
        raw?.destroy();
      } catch (_) {}
    }
  }
  return (minLatency, success);
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
  final int successCount;
  LatencyResult(this.node, this.latencyMs, [this.successCount = 0]);
}

/// 对节点列表做并发延迟测试。
///
/// 对应旧版 tester.py 的 run_tcp_tests_async：每个节点测 [probes] 次，
/// 成功率 (< [minSuccessRate]) 的节点被丢弃（与旧版 min_success_rate 一致）。
/// [sni] 非空时，probe 会做「TCP + TLS 握手」延迟测量（贴近 vless/WS 代理真实建连）。
/// 返回按 (-successCount, latency) 排序的结果，以及测试/连通计数。
Future<(List<LatencyResult>, int tested, int connected)> latencyProbeAll(
  List<String> nodes, {
  required Duration timeout,
  required int workers,
  int probes = 1,
  double minSuccessRate = 1.0,
  Map<String, String>? nodeSource,
  String? sni,
  Future<(double?, int)> Function(String ip, int port, Duration timeout, {int probes, String? sni})? probe,
  void Function(String)? onLog,
}) async {
  final logBuf = <String>[];
  Timer? flushTimer;
  void flushLog() {
    if (logBuf.isEmpty) return;
    final batch = logBuf.join('\n');
    logBuf.clear();
    onLog?.call(batch);
  }

  void scheduleLogFlush() {
    flushTimer ??= Timer(const Duration(milliseconds: 120), () {
      flushTimer = null;
      flushLog();
      if (logBuf.isNotEmpty) scheduleLogFlush();
    });
  }

  final targets = <(String, IpPort, int)>[];
  for (final node in nodes) {
    final ep = parseEndpoint(node);
    if (ep != null) targets.add((node, ep.$1, ep.$2));
  }

  final results = <LatencyResult>[];
  final semaphore = _Semaphore(workers);
  var done = 0;
  await Future.wait(targets.map((t) async {
    await semaphore.acquire();
    try {
      final (lat, ok) = await (probe ?? measureLatency)(t.$2, t.$3, timeout, probes: probes, sni: sni);
      // 成功率过滤：与旧版一致，success/tcp_probes < min_success_rate 丢弃
      final rate = probes > 0 ? ok / probes : 0.0;
      final okLat = (lat != null && rate >= minSuccessRate);
      if (okLat) {
        results.add(LatencyResult(t.$1, lat, ok));
      } else {
        results.add(LatencyResult(t.$1, null, ok));
      }
      // 单节点明细日志（每测完一个即输出 ip 与其延迟/结果）
      done++;
      final ep = '${t.$2}:${t.$3}';
      final line = okLat
          ? '  [$done/${targets.length}] $ep  ${lat.toStringAsFixed(1)} ms'
          : '  [$done/${targets.length}] $ep  超时/失败';
      logBuf.add(line);
      scheduleLogFlush();
    } finally {
      semaphore.release();
    }
  }));
  flushLog();

  final succeeded = results.where((r) => r.latencyMs != null).toList()
    ..sort((a, b) {
      final sc = b.successCount.compareTo(a.successCount);
      if (sc != 0) return sc;
      return a.latencyMs!.compareTo(b.latencyMs!);
    });
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
