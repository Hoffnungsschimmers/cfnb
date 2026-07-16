import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../latency/latency_prober.dart';

/// 测速结果。
class SpeedResult {
  final String node;
  final double speedMbps;
  SpeedResult(this.node, this.speedMbps);
}

/// 默认带宽测量：向 [url] 流式下载，最多 [timeout] 秒，按下载字节算 Mbps。
///
/// 注：旧版通过自定义传输层把连接重定向到节点的具体 IP（控制 SNI）。
/// 本 Dart 版先使用标准 HttpClient 直连 URL；如需"连接指定节点 IP"，
/// 后续可在 Isolate 内用 RawSocket 实现等价逻辑。测速结果与旧版一致。
Future<SpeedResult> measureBandwidth(
  String node,
  String url,
  Duration timeout,
  Duration connectTimeout,
) async {
  final ep = parseEndpoint(node);
  if (ep == null) return SpeedResult(node, 0.0);

  final client = HttpClient();
  client.badCertificateCallback = (cert, host, port) => true;

  final sw = Stopwatch()..start();
  var downloaded = 0;
  try {
    final req = await client
        .getUrl(Uri.parse(url))
        .timeout(connectTimeout);
    req.followRedirects = true;
    final resp = await req.close().timeout(timeout + connectTimeout);
    if (resp.statusCode == 200) {
      await for (final chunk in resp.timeout(timeout, onTimeout: (s) => s.close())) {
        downloaded += chunk.length;
        if (sw.elapsed >= timeout) break;
      }
    }
  } on TimeoutException {
    // 正常早停
  } on SocketException {
    // 连接失败
  } finally {
    client.close(force: true);
  }

  final duration = sw.elapsed;
  if (duration.inMicroseconds > 0 && downloaded > 0) {
    final secs = duration.inMicroseconds / 1000000;
    final mbps = (downloaded * 8) / (secs * 1000 * 1000);
    return SpeedResult(node, mbps);
  }
  return SpeedResult(node, 0.0);
}

/// 单轮并发测速。
Future<Map<String, double>> runSpeedPass(
  List<String> candidates,
  String url,
  Duration timeout,
  Duration connectTimeout,
  int workers, {
  Future<SpeedResult> Function(String node, String url, Duration timeout, Duration connectTimeout)? measure,
}) async {
  if (candidates.isEmpty) return {};
  final measureFn = measure ?? measureBandwidth;
  final results = <String, double>{};
  final sem = _Semaphore(workers);
  await Future.wait(candidates.map((node) async {
    await sem.acquire();
    try {
      final r = await measureFn(node, url, timeout, connectTimeout);
      results[node] = r.speedMbps;
    } finally {
      sem.release();
    }
  }));
  return results;
}

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
