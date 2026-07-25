import 'dart:async';
import 'dart:io';
import 'dart:math' show sqrt;

/// 解析 `IP:端口#CC 来源` 节点行，返回 (ip, port)。
/// 支持 IPv4、[IPv6]:port、裸 IPv6:port 三种格式。
(IpPort, int)? parseEndpoint(String node) {
  // 取 # 之前的部分（ip:port 部分）
  final base = node.split('#').first.trim();
  if (base.isEmpty) return null;

  String ip;
  String portStr;
  if (base.startsWith('[')) {
    // IPv6 方括号格式: [2001:db8::1]:443
    final closeBracket = base.indexOf(']');
    if (closeBracket < 0) return null;
    ip = base.substring(1, closeBracket);
    // ] 后应跟 :port
    if (closeBracket + 1 >= base.length || base[closeBracket + 1] != ':') return null;
    portStr = base.substring(closeBracket + 2);
  } else {
    final idx = base.lastIndexOf(':');
    if (idx < 0) return null;
    ip = base.substring(0, idx);
    portStr = base.substring(idx + 1);
    // 区分 IPv4:port 与 IPv6:port：IPv6 地址含多个冒号
    if (ip.contains(':')) {
      // 裸 IPv6:port — 验证 IPv6 格式（至少含 2 个冒号）
      if (!ip.contains('::') && ip.split(':').length < 3) return null;
    }
  }
  final port = int.tryParse(portStr.trim());
  if (port == null || port <= 0 || port > 65535) return null;
  return (ip, port);
}

typedef IpPort = String;

/// 测量到 (ip, port) 的 TCP 连接延迟（毫秒）。
///
/// 串行 [probes] 次连接，返回 (最小延迟, 抖动标准差, 成功次数)。
/// 抖动越小表示节点越稳定。一次都没成功时返回 (null, null, 0)。
Future<(double?, double?, int)> measureLatency(
  String ip,
  int port,
  Duration timeout, {
  int probes = 1,
}) async {
  final latencies = <double>[];
  for (var i = 0; i < probes; i++) {
    final sw = Stopwatch()..start();
    try {
      final sock = await Socket.connect(ip, port, timeout: timeout);
      await sock.close();
      latencies.add(sw.elapsedMilliseconds.toDouble());
    } on SocketException {
      // 本次失败，继续
    } on TimeoutException {
      // 本次超时，继续
    }
  }
  if (latencies.isEmpty) return (null, null, 0);
  final min = latencies.reduce((a, b) => a < b ? a : b);
  final jitter = latencies.length >= 2 ? _stdDev(latencies) : 0.0;
  return (min, jitter, latencies.length);
}

/// 计算标准差（√方差）。
double _stdDev(List<double> values) {
  final mean = values.reduce((a, b) => a + b) / values.length;
  final sumSq = values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b);
  final variance = sumSq / values.length;
  return variance.isNaN ? 0.0 : sqrt(variance);
}

/// 提取节点注释里的国家码（# 之后、来源之前）。
/// 兼容新格式 `#HK CM` 和旧格式 `#HK@CM`。
String nodeCountry(String node) {
  final hashIdx = node.indexOf('#');
  if (hashIdx < 0) return '';
  final afterHash = node.substring(hashIdx + 1);
  // 国家码在空格或 @ 之前
  final spaceIdx = afterHash.indexOf(' ');
  final atIdx = afterHash.indexOf('@');
  int endIdx = afterHash.length;
  if (spaceIdx >= 0 && (atIdx < 0 || spaceIdx < atIdx)) {
    endIdx = spaceIdx;
  } else if (atIdx >= 0) {
    endIdx = atIdx;
  }
  return afterHash.substring(0, endIdx).trim();
}

/// 延迟测试结果。
class LatencyResult {
  final String node;
  final double? latencyMs;
  final double? jitterMs; // 抖动（标准差），越小越稳定
  final int successCount;
  LatencyResult(this.node, this.latencyMs, [this.jitterMs, this.successCount = 0]);
}

/// 对节点列表做并发延迟测试。
///
/// 对应旧版 tester.py 的 run_tcp_tests_async：每个节点测 [probes] 次，
/// 成功率 (< [minSuccessRate]) 的节点被丢弃（与旧版 min_success_rate 一致）。
/// 返回按 (-successCount, latency) 排序的结果，以及测试/连通计数。
Future<(List<LatencyResult>, int tested, int connected)> latencyProbeAll(
  List<String> nodes, {
  required Duration timeout,
  required int workers,
  int probes = 1,
  double minSuccessRate = 1.0,
  Map<String, String>? nodeSource,
  Future<(double?, double?, int)> Function(String ip, int port, Duration timeout, {int probes})? probe,
  void Function(String)? onLog,
  /// 取消检查：返回 true 时跳过后续节点探测。
  bool Function()? isCancelled,
  /// 节点完成回调：每完成一个节点探测即时触发（不节流），
  /// 携带 (done=已探测, total=总节点数, connected=已连通) 供 UI 进度条精确刷新。
  void Function(int done, int total, int connected)? onProgress,
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
  var connected = 0;
  var cancelled = false;
  await Future.wait(targets.map((t) async {
    // 排队前检查取消：避免已排队的 future 逐个等 semaphore
    if (cancelled || (isCancelled != null && isCancelled())) {
      cancelled = true;
      return;
    }
    await semaphore.acquire();
    try {
      // 获取信号量后再次检查取消
      if (cancelled || (isCancelled != null && isCancelled())) {
        cancelled = true;
        return;
      }
      final (lat, jitter, ok) = await (probe ?? measureLatency)(t.$2, t.$3, timeout, probes: probes);
      // 探测完成后检查取消
      if (cancelled || (isCancelled != null && isCancelled())) {
        cancelled = true;
        return;
      }
      // 成功率过滤
      final rate = probes > 0 ? ok / probes : 0.0;
      final okLat = (lat != null && rate >= minSuccessRate);
      if (okLat) {
        results.add(LatencyResult(t.$1, lat, jitter, ok));
      } else {
        results.add(LatencyResult(t.$1, null, null, ok));
      }
      // 单节点明细日志（每测完一个即输出 ip 与其延迟/结果）
      done++;
      if (okLat) connected++;
      // 即时进度回调（不节流，UI 层自管刷新节流，见 SubscriptionsNotifier）。
      onProgress?.call(done, targets.length, connected);
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
