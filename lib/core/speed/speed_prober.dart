import 'dart:async';
import 'dart:io';

import '../latency/latency_prober.dart';

/// 带宽测速：向目标 IP:port 直连下载 Cloudflare 测速负载，统计吞吐 (Mbps)。
///
/// 对应旧版 speed.py 的 measure_bandwidth_async：
/// 用自定义连接后端把 HTTPS 请求定向到指定 IP（SNI/Host 仍用 speed.cloudflare.com），
/// 流式下载并在超时前停止，按 字节数/耗时 推算带宽。
/// 返回 null 表示无速度（超时/失败）。
Future<double?> measureBandwidth(
  String ip,
  int port,
  Duration timeout, {
  int bytes = 1 * 1024 * 1024,
  String host = 'speed.cloudflare.com',
  int connectTimeoutMs = 5000,
}) async {
  final ctx = SecurityContext(withTrustedRoots: false);
  final client = HttpClient()..badCertificateCallback = (a, b, c) => true;
  client.connectionFactory = (uri, proxyHost, proxyPort) {
    final Future<Socket> socketFuture = (() async {
      final raw = await Socket.connect(ip, port,
          timeout: Duration(milliseconds: connectTimeoutMs));
      return SecureSocket.secure(
        raw,
        context: ctx,
        host: host,
        onBadCertificate: (a) => true,
      );
    })();
    return Future.value(ConnectionTask.fromSocket(socketFuture, () {}));
  };

  final sw = Stopwatch()..start();
  var downloaded = 0;
  try {
    final req = await client.getUrl(Uri.parse('https://$host/__down?bytes=$bytes'));
    final resp = await req.close();
    if (resp.statusCode == 200) {
      await for (final chunk in resp) {
        downloaded += chunk.length;
        if (sw.elapsed >= timeout) break;
      }
    }
  } on Object {
    // 超时/连接失败：视为无速度
  } finally {
    client.close(force: true);
  }

  final dur = sw.elapsedMilliseconds / 1000;
  if (dur > 0 && downloaded > 0) {
    return (downloaded * 8) / (dur * 1000 * 1000);
  }
  return null;
}

/// 对节点列表并发测带宽，返回 节点 -> Mbps（无速度为 null）。
///
/// 若 [probes] > 1，则对每个节点测速多次并取**中位数**，抑制单点抖动（CF 边缘吞吐波动大）。
Future<Map<String, double?>> measureBandwidthAll(
  List<String> nodes, {
  required Duration timeout,
  int bytes = 1 * 1024 * 1024,
  int workers = 20,
  int probes = 1,
  void Function(String)? onLog,
}) async {
  final targets = <(String, String, int)>[];
  for (final node in nodes) {
    final ep = parseEndpoint(node);
    if (ep != null) targets.add((node, ep.$1, ep.$2));
  }

  final result = <String, double?>{};
  final sem = _SpeedSem(targets.length < workers ? targets.length : workers);
  var done = 0;
  await Future.wait(targets.map((t) async {
    await sem.acquire();
    try {
      final mbps = await measureBandwidthSamples(t.$2, t.$3, timeout,
          bytes: bytes, probes: probes);
      result[t.$1] = mbps;
      done++;
      if (onLog != null) {
        final ep = '${t.$2}:${t.$3}';
        if (mbps != null) {
          onLog('  [$done/${targets.length}] $ep  带宽 ${mbps.toStringAsFixed(2)} Mbps');
        } else {
          onLog('  [$done/${targets.length}] $ep  无速度');
        }
      }
    } finally {
      sem.release();
    }
  }));
  return result;
}

/// 对单个节点多次测速并取中位数（[probes]=1 时退化为单次）。
/// 任一采样返回 null 则忽略该次；多次全失败时返回 null。
Future<double?> measureBandwidthSamples(
  String ip,
  int port,
  Duration timeout, {
  int bytes = 1 * 1024 * 1024,
  int probes = 1,
}) async {
  final samples = <double>[];
  for (var i = 0; i < (probes < 1 ? 1 : probes); i++) {
    final v = await measureBandwidth(ip, port, timeout, bytes: bytes);
    if (v != null) samples.add(v);
  }
  if (samples.isEmpty) return null;
  samples.sort();
  return samples[samples.length ~/ 2];
}

/// 简易信号量（限制并发下载数）。
class _SpeedSem {
  int _count;
  final _queue = <Completer<void>>[];
  _SpeedSem(this._count);
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
