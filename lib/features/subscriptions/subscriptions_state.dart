import 'dart:io';

import 'package:dio/dio.dart' as dio_pkg;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/config/app_config.dart';
import '../../core/github/github_push.dart';
import '../../core/latency/latency_filter.dart';
import '../../core/latency/latency_prober.dart';
import '../../core/subscription/subscription_converter.dart';
import '../results/result_state.dart';

/// 订阅器状态：仅保留「订阅IP」与「延迟优选」两个动作，含运行中标记。
class SubscriptionsState {
  final bool running;
  SubscriptionsState({this.running = false});
  SubscriptionsState copyWith({bool? running}) =>
      SubscriptionsState(running: running ?? this.running);
}

class SubscriptionsNotifier extends StateNotifier<SubscriptionsState> {
  final Ref ref;
  SubscriptionsNotifier(this.ref) : super(SubscriptionsState());

  /// 单独：订阅IP（转换订阅器 -> addressesapi.txt）。
  Future<void> runSubscription() async {
    if (state.running) return;
    final cfg = await _cfg();
    final parser = await ref.read(nodeParserProvider.future);
    final logger = ref.read(subLoggerProvider);
    state = state.copyWith(running: true);
    logger.info('开始「订阅IP」转换');
    try {
      if (!cfg.subConvertEnabled) {
        logger.info('订阅转换未启用（subConvertEnabled=false）');
        return;
      }
      final (nodes, srcMap) = await convertSubscriptions(
        cfg,
        fetch: (url) => _safeFetch(url),
        resolve: _resolveHost,
        parser: parser,
        onLog: (m) => logger.info(m),
      );
      if (nodes.isEmpty) {
        logger.info('订阅转换无可用节点（请检查 subGenerators/subUrls 配置）');
      } else {
        await writeSubOutput(nodes, cfg.subOutputFile);
        await writeSourceMap(srcMap, cfg.subOutputFile);
        await ref.read(resultProvider.notifier).loadFile(cfg.subOutputFile);
        logger.info('订阅IP转换完成：${nodes.length} 个节点 -> ${cfg.subOutputFile}');
      }
    } catch (e) {
      logger.error(e.toString());
    } finally {
      state = state.copyWith(running: false);
    }
  }

  /// 单独：延迟优选（对订阅IP做延迟测试，保留前 N 名 -> addressesapi_top.txt）。
  Future<void> runLatency() async {
    if (state.running) return;
    final cfg = await _cfg();
    final logger = ref.read(subLoggerProvider);
    state = state.copyWith(running: true);
    logger.info('开始「延迟优选」');
    try {
      final nodes = await _readNodes(cfg.subOutputFile);
      if (nodes.isEmpty) {
        logger.info('未找到订阅IP文件（${cfg.subOutputFile}），请先运行「订阅IP」');
      } else {
        final (kept, tested, connected) = await LatencyFilter.run(
          nodes: nodes,
          outputFile: cfg.subLatencyOutputFile,
          latencyMaxMs: cfg.subLatencyMaxMs,
          timeout: Duration(milliseconds: (cfg.subLatencyTimeout * 1000).round()),
          workers: cfg.subLatencyWorkers,
          probes: cfg.subLatencyProbes,
          minSuccessRate: 1.0,
          speedEnabled: cfg.subSpeedEnabled,
          speedLatencyLimitMs: cfg.subSpeedLatencyLimit,
          qualityLatencyWeight: cfg.subQualityLatencyWeight,
          topN: cfg.subLatencyTopN > 0 ? cfg.subLatencyTopN : 100000,
          speedTimeout: Duration(milliseconds: (cfg.subSpeedTimeout * 1000).round()),
          speedBytes: (cfg.subSpeedSizeMb * 1024 * 1024).round(),
          speedWorkers: cfg.subSpeedWorkers,
          probe: measureLatency,
          onLog: (m) => logger.info(m),
        );
        logger.info('延迟优选完成：测试 $tested / 连通 $connected / 保留 ${kept.length}');
        await ref.read(resultProvider.notifier).loadFile(cfg.subLatencyOutputFile);
      }
    } catch (e) {
      logger.error(e.toString());
    } finally {
      state = state.copyWith(running: false);
    }
  }

  Future<AppConfig> _cfg() async {
    final repo = await ref.read(configRepositoryProvider.future);
    return repo.current;
  }

  GithubPush? _github(AppConfig cfg) =>
      cfg.githubToken.isEmpty ? null : GithubPush(token: cfg.githubToken, repo: cfg.githubRepo, branch: cfg.githubBranch);

  /// 手动推送单个产物文件到 GitHub（cf-ip 仓）。返回 (是否成功, HTTP码, 消息)。
  /// 未配置 Token / 文件不存在时返回失败原因，不抛异常。
  Future<(bool, int, String)> pushFile(String file) async {
    if (!GithubPush.isPushable(file)) {
      final m = '仅支持推送后缀为 _top.txt 的优选结果文件（当前：$file）';
      ref.read(subLoggerProvider).info(m);
      return (false, 0, m);
    }
    final cfg = await _cfg();
    final logger = ref.read(subLoggerProvider);
    final github = _github(cfg);
    if (github == null) {
      final m = 'GitHub 未配置（请在设置填写 Token/Repo/Branch），跳过推送：$file';
      logger.info(m);
      return (false, 0, m);
    }
    if (!File(file).existsSync()) {
      final m = '文件不存在：$file';
      logger.error(m);
      return (false, 0, m);
    }
    try {
      final content = await File(file).readAsString();
      logger.info('开始推送 $file 到 GitHub（${cfg.githubRepo}@${cfg.githubBranch}）…');
      final code = await github.pushFile(file, content, message: 'update $file');
      logger.info('已推送 $file (HTTP $code)');
      return (true, code, '已推送 $file (HTTP $code)');
    } catch (e) {
      final m = '推送 $file 失败：$e';
      logger.error(m);
      return (false, 0, m);
    }
  }

  // ---- 网络辅助 ----
  // 复用 GithubPush 的直连 Dio（走系统代理，适用于订阅源抓取）。
  final _dio = GithubPush.directDio();

  Future<String> _httpFetch(String url, {Duration? connectTimeout}) async {
    final resp = await _dio.get(url,
        options: dio_pkg.Options(
          responseType: dio_pkg.ResponseType.plain,
          headers: {
            'User-Agent': edgetunnelUa,
            'Accept': '*/*',
          },
          connectTimeout: connectTimeout ?? const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 20),
        ));
    return resp.data.toString();
  }

  /// 容错抓取：单次尝试，失败只记录一次并跳过，不重试、不中断整体转换。
  /// （死源/TLS 握手失败属源自身问题，重试无意义；多候选 URL 的回退在 convertSubscriptions 内处理。）
  Future<String> _safeFetch(String url) async {
    final logger = ref.read(subLoggerProvider);
    try {
      return await _httpFetch(url);
    } catch (e) {
      final msg = e.toString().replaceAll(RegExp(r'\n'), ' ');
      // edgetunnel 系订阅器返回 403，通常是该部署未启用 BEST_SUB：
      // 需在 Cloudflare Workers 变量中设置 BEST_SUB=1（或 true），本工具的
      // host=example.com / uuid=00000000... / edgetunnel UA 才会被识别为优选订阅生成器。
      final hint = (msg.contains('403') && url.contains('/sub'))
          ? '（该 edgetunnel 部署可能未启用 BEST_SUB：请在 Cloudflare 变量设置 BEST_SUB=1）'
          : '';
      logger.error('抓取失败 [$url]：$msg$hint');
      return '';
    }
  }

  Future<String?> _resolveHost(String host) async {
    if (_isIp(host)) return host;
    try {
      final list = await InternetAddress.lookup(host);
      return list.isNotEmpty ? list.first.address : null;
    } on Object {
      return null;
    }
  }

  bool _isIp(String host) {
    if (host.contains(':')) {
      final h = host.replaceAll(RegExp(r'[\[\]]'), '');
      return h.contains(RegExp(r'^[0-9a-fA-F:]+$'));
    }
    final parts = host.split('.');
    if (parts.length != 4) return false;
    return parts.every((p) => int.tryParse(p) != null);
  }

  Future<List<String>> _readNodes(String path) async {
    final f = File(path);
    if (!f.existsSync()) return [];
    final text = await f.readAsString();
    return text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && !e.startsWith('#'))
        .toList();
  }
}

final subProvider = StateNotifierProvider<SubscriptionsNotifier, SubscriptionsState>(
    (ref) => SubscriptionsNotifier(ref));
