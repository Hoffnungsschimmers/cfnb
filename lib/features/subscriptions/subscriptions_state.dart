import 'dart:io';

import 'package:dio/dio.dart' as dio_pkg;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/providers.dart';
import '../../core/config/app_config.dart';
import '../../core/github/github_push.dart';
import '../../core/latency/latency_filter.dart';
import '../../core/latency/latency_prober.dart';
import '../../core/net/ip.dart';
import '../../core/net/retry.dart';
import '../../core/subscription/subscription_converter.dart';
import '../results/result_state.dart';

/// 走 Dio 带 cfg 化超时与指数退避重试的 HTTP GET，返回 body 明文。
///
/// 成功响应 (status 200-299) 直接返回 `.data.toString()`；其它状态码被 Dio
/// 默认的 `validateStatus` 判定并转换成 [dio_pkg.DioException]，由
/// [retry] 捕获并触发下一次尝试。
///
/// - 三档超时 (`connectTimeout`/`sendTimeout`/`receiveTimeout`) 与 `maxRetries`
///   由调用方从 [AppConfig] 注入；本函数只在内部做 `clamp` 防御非法值。
/// - `sleep` 默认为 [Future.delayed]；测试可注入 mock 以跳过真实指数退避。
/// - `maxRetries` 语义：`0` 表示不重试（只走第一次），与 [retry] 一致。
Future<String> fetchHttpWithRetry({
  required dio_pkg.Dio dio,
  required String url,
  required int connectTimeoutSec,
  required int sendTimeoutSec,
  required int receiveTimeoutSec,
  required int maxRetries,
  required int retryDelayMs,
  Future<void> Function(Duration)? sleep,
}) async {
  Future<String> doGet() async {
    final resp = await dio.get<String>(
      url,
      options: dio_pkg.Options(
        responseType: dio_pkg.ResponseType.plain,
        headers: const {
          'User-Agent': edgetunnelUa,
          'Accept': '*/*',
        },
        connectTimeout: Duration(seconds: connectTimeoutSec.clamp(1, 300)),
        sendTimeout: Duration(seconds: sendTimeoutSec.clamp(1, 600)),
        receiveTimeout: Duration(seconds: receiveTimeoutSec.clamp(1, 600)),
      ),
    );
    return resp.data.toString();
  }

  return retry<String>(
    doGet,
    maxRetries: maxRetries.clamp(0, 10),
    initialDelay: Duration(milliseconds: retryDelayMs),
    sleep: sleep,
  );
}

/// 把抓取异常分类为可读提示（供日志/排障）。纯函数。
String classifyFetchError(Object e, String url) {
  if (e is dio_pkg.DioException) {
    final t = e.type;
    if (t == dio_pkg.DioExceptionType.connectionTimeout ||
        t == dio_pkg.DioExceptionType.sendTimeout) {
      return '连接超时（源不可达或被墙）';
    }
    if (t == dio_pkg.DioExceptionType.receiveTimeout) {
      return '读取超时（响应过慢）';
    }
    if (t == dio_pkg.DioExceptionType.badResponse) {
      final code = e.response?.statusCode;
      final hint = (code == 403 && url.contains('/sub'))
          ? '（该 edgetunnel 部署可能未启用 BEST_SUB：请在 Cloudflare 变量设置 BEST_SUB=1）'
          : '';
      return 'HTTP ${code ?? '?'} 错误$hint';
    }
    if (t == dio_pkg.DioExceptionType.connectionError) {
      return '连接失败（DNS/网络不可达）';
    }
    return '请求异常：${e.message ?? e}';
  }
  return '未知错误：$e';
}

/// 订阅器状态：仅保留「订阅IP」与「延迟优选」两个动作，含运行中标记。
class SubscriptionsState {
  final bool running;
  SubscriptionsState({this.running = false});
  SubscriptionsState copyWith({bool? running}) =>
      SubscriptionsState(running: running ?? this.running);
}

class SubscriptionsNotifier extends StateNotifier<SubscriptionsState> {
  final Ref ref;

  /// 长生命周期安全 Dio（走系统代理、校验 TLS 证书）。
  final dio_pkg.Dio _dioSafe = GithubPush.directDio();

  /// 长生命周期跳过证书校验的 Dio（自签名/过期证书源）。
  late final dio_pkg.Dio _dioInsecure = (() {
    final d = GithubPush.directDio();
    d.options.validateStatus = (_) => true;
    (d.httpClientAdapter as dynamic).createHttpClient = () {
      return HttpClient()..badCertificateCallback = (_, _, _) => true;
    };
    return d;
  })();

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
        fetch: (url) => _safeFetch(url, cfg.subInsecure, cfg),
        resolve: _resolveHost,
        parser: parser,
        onLog: (m) => logger.info(m),
      );
      if (nodes.isEmpty) {
        logger.info('订阅转换无可用节点（请检查 subGenerators/subUrls 配置）');
      } else {
        final outPath = await _resolve(cfg.subOutputFile);
        await writeSubOutput(nodes, outPath);
        await writeSourceMap(srcMap, outPath);
        await ref.read(resultProvider.notifier).loadFile(outPath);
        logger.info('订阅IP转换完成：${nodes.length} 个节点 -> $outPath');
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
      final nodes = await _readNodes(await _resolve(cfg.subOutputFile));
      if (nodes.isEmpty) {
        logger.info('未找到订阅IP文件（${cfg.subOutputFile}），请先运行「订阅IP」');
      } else {
        final latencyOut = await _resolve(cfg.subLatencyOutputFile);
        final (kept, tested, connected) = await LatencyFilter.run(
          nodes: nodes,
          outputFile: latencyOut,
          latencyMaxMs: cfg.subLatencyMaxMs,
          timeout: Duration(milliseconds: (cfg.subLatencyTimeout * 1000).round()),
          workers: cfg.subLatencyWorkers,
          probes: cfg.subLatencyProbes,
          minSuccessRate: cfg.subLatencyMinSuccessRate,
          topN: cfg.subLatencyTopN > 0 ? cfg.subLatencyTopN : 100000,
          probe: measureLatency,
          onLog: (m) => logger.info(m),
        );
        logger.info('延迟优选完成：测试 $tested / 连通 $connected / 保留 ${kept.length}');
        await ref.read(resultProvider.notifier).loadFile(latencyOut);
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

  Future<String> _resolve(String name) async {
    final dir = await getApplicationDocumentsDirectory();
    return resolveOutputPath(name, dir.path);
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
  // 订阅源抓取共用顶层函数 [fetchHttpWithRetry]。`_dioSafe` 走系统代理并校验
  // TLS 证书，`_dioInsecure` 跳过证书校验以兼容自签/过期证书源。两个 Dio 均为
  // 长生命周期实例，复用 TCP 连接（keep-alive）。

  /// 容错抓取：失败按 [AppConfig] 重试到耗尽，最终失败仅记录并返回空串，
  /// 不中断整体转换。多候选 URL 的回退在 convertSubscriptions 内处理。
  Future<String> _safeFetch(String url, bool certInsecure, AppConfig cfg) async {
    final logger = ref.read(subLoggerProvider);
    final dio = certInsecure ? _dioInsecure : _dioSafe;
    try {
      return await fetchHttpWithRetry(
        dio: dio,
        url: url,
        connectTimeoutSec: cfg.subFetchConnectTimeout,
        sendTimeoutSec: cfg.subFetchTimeout,
        receiveTimeoutSec: cfg.subFetchTimeout,
        maxRetries: cfg.subFetchMaxRetries.clamp(0, 10),
        retryDelayMs: (cfg.subFetchRetryDelay * 1000).round(),
      );
    } catch (e) {
      logger.error('抓取失败 [$url]：${classifyFetchError(e, url)}');
      return '';
    }
  }

  Future<String?> _resolveHost(String host) async {
    if (isIp(host)) return host;
    try {
      final list = await InternetAddress.lookup(host);
      return list.isNotEmpty ? list.first.address : null;
    } on Object {
      return null;
    }
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
