import 'dart:math';

import '../config/app_config.dart';
import 'speed_prober.dart';

/// 带宽测速编排（对应旧版 speed.py 的 run_multi_pass / with_retry）。
class SpeedRunner {
  /// 两轮漏斗式测速：探速(小文件高并发) -> 精测(大文件低并发，早停)。
  static Future<List<SpeedResult>> runMultiPass(
    List<String> candidates,
    AppConfig config, {
    Future<SpeedResult> Function(String node, String url, Duration timeout, Duration connectTimeout)? measure,
  }) async {
    if (candidates.isEmpty) return [];

    // 探速轮
    final probeBytes = 262144;
    final probeUrl = config.bandwidthUrlTemplate.replaceAll('{bytes}', '$probeBytes');
    final probeSpeed = await runSpeedPass(
      candidates,
      probeUrl,
      Duration(seconds: 4),
      Duration(seconds: 2),
      config.bandwidthWorkers,
      measure: measure,
    );

    final fastNodes = probeSpeed.keys.toList()
      ..sort((a, b) => probeSpeed[b]!.compareTo(probeSpeed[a]!));
    if (fastNodes.isEmpty) return [];

    // 精测轮：前 300 名，1MB
    const refineTopN = 300;
    final refineCandidates = fastNodes.take(refineTopN).toList();
    final refineBytes = 1 * 1024 * 1024;
    final refineUrl = config.bandwidthUrlTemplate.replaceAll('{bytes}', '$refineBytes');
    final earlyStop = config.globalTopN * 3;
    final refineSpeed = await runSpeedPass(
      refineCandidates,
      refineUrl,
      Duration(seconds: 15),
      Duration(seconds: 5),
      max(1, config.bandwidthWorkers ~/ 2),
      measure: measure,
    );

    // 合并：精测优先，探速兜底
    final finalSpeed = <String, double>{};
    for (final node in fastNodes) {
      if (refineSpeed.containsKey(node) && refineSpeed[node]! > 0) {
        finalSpeed[node] = refineSpeed[node]!;
      } else if (probeSpeed.containsKey(node) && probeSpeed[node]! > 0) {
        finalSpeed[node] = probeSpeed[node]!;
      }
    }

    final results = finalSpeed.entries
        .map((e) => SpeedResult(e.key, e.value))
        .toList()
      ..sort((a, b) => b.speedMbps.compareTo(a.speedMbps));
    return results;
  }

  /// 带重试的整体测速。
  static Future<List<SpeedResult>> runWithRetry(
    List<String> candidates,
    AppConfig config, {
    Future<SpeedResult> Function(String node, String url, Duration timeout, Duration connectTimeout)? measure,
  }) async {
    if (candidates.isEmpty) return [];
    for (var attempt = 1; attempt <= config.bandwidthRetryMax; attempt++) {
      final results = await runMultiPass(candidates, config, measure: measure);
      if (results.isNotEmpty) return results;
      if (attempt < config.bandwidthRetryMax) {
        await Future.delayed(Duration(seconds: config.bandwidthRetryDelay));
      }
    }
    return [];
  }
}
