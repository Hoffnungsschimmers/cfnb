import 'dart:async';
import 'dart:io';

import '../latency/latency_prober.dart';

/// 判断是否为 Cloudflare 任播 IP（edgetunnel 类节点）。
bool isCloudflareIp(String ip) {
  // 覆盖 Cloudflare 常见网段（非穷举，足以区分订阅器里的 CF 与 VPS 节点）。
  const prefixes = [
    '162.159.', '162.158.', '104.16.', '104.17.', '104.18.', '104.19.',
    '104.20.', '104.21.', '104.22.', '104.23.', '104.24.', '104.25.',
    '104.26.', '104.27.', '104.28.', '104.29.', '104.30.', '104.31.',
    '172.64.', '172.65.', '172.66.', '172.67.', '172.68.', '141.101.',
    '188.114.', '188.115.', '197.234.240.', '198.41.', '131.0.72.',
    '103.21.244.', '103.22.200.', '103.23.145.', '103.31.4.', '2606:4700:',
  ];
  for (final p in prefixes) {
    if (ip.startsWith(p)) return true;
  }
  return false;
}

/// 带宽测速：向目标 IP:port 直连做 TLS 后下载真实数据，统计吞吐 (Mbps)。
///
/// 与旧版不同——**不再绑定 speed.cloudflare.com 这一固定域名**：
/// - Cloudflare 节点：Host 用 `speed.cloudflare.com`，CDN 会按目标 IP 路由到对应边缘，
///   下载 `/__down?bytes=` 得到真实边缘吞吐。
/// - 非 Cloudflare 节点（VPS/直连）：Host/SNI 用该节点 IP 本身，对其开放端口上的真实
///   HTTP 服务发起下载测吞吐（这些节点多为代理面板/Web，可直接取数据）。
///
/// 返回 null 表示无速度（超时/握手失败/无可用服务）。
Future<double?> measureBandwidth(
  String ip,
  int port,
  Duration timeout, {
  int bytes = 10 * 1024 * 1024,
  String? host,
  int connectTimeoutMs = 8000,
}) async {
  final isCf = isCloudflareIp(ip);
  final useHost = host ?? (isCf ? 'speed.cloudflare.com' : ip);
  final path = isCf ? '/__down?bytes=$bytes' : '/';

  final ctx = SecurityContext(withTrustedRoots: false);
  final client = HttpClient()..badCertificateCallback = (a, b, c) => true;
  client.connectionFactory = (uri, proxyHost, proxyPort) {
    final future = (() async {
      final raw = await Socket.connect(ip, port,
          timeout: Duration(milliseconds: connectTimeoutMs));
      return SecureSocket.secure(
        raw,
        context: ctx,
        host: useHost,
        onBadCertificate: (_) => true,
      );
    })();
    return Future.value(ConnectionTask.fromSocket(future, () {}));
  };

  final sw = Stopwatch()..start();
  var downloaded = 0;
  try {
    final req = await client.getUrl(Uri.parse('https://$useHost$path'));
    final resp = await req.close();
    if (resp.statusCode == 200) {
      await for (final chunk in resp) {
        downloaded += chunk.length;
        if (sw.elapsed >= timeout) break;
      }
    } else {
      // 非 200（如节点首页），仍用已下载量估算（至少证明可达且有服务）
      if (downloaded == 0) return null;
    }
  } on Object {
    // 超时/连接失败/握手失败：视为无速度
  } finally {
    client.close(force: true);
  }

  final dur = sw.elapsedMilliseconds / 1000;
  if (dur > 0 && downloaded > 0) {
    // 非 CF 节点若首页很小，下载会被瞬间完成导致吞吐虚高——用「实际耗时」归一，
    // 避免小页面被算成几百 Mbps。最短按 1 秒有效下载时间计。
    final effective = dur < 1.0 ? 1.0 : dur;
    return (downloaded * 8) / (effective * 1000 * 1000);
  }
  return null;
}

/// 对节点列表并发测带宽，返回 节点 -> Mbps（无速度为 null）。
///
/// 若 [probes] > 1，则对每个节点测速多次并取**中位数**，抑制单点抖动（边缘吞吐波动大）。
Future<Map<String, double?>> measureBandwidthAll(
  List<String> nodes, {
  required Duration timeout,
  int bytes = 10 * 1024 * 1024,
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
  int bytes = 10 * 1024 * 1024,
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
