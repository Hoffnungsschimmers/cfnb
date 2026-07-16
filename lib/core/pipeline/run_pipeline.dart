import 'dart:io';

import '../config/app_config.dart';
import '../fetch/node_parser.dart';
import '../fetch/node_source.dart';
import '../github/github_push.dart';
import '../latency/latency_filter.dart';
import '../latency/latency_prober.dart';
import '../output/ip_writer.dart';
import '../speed/speed_prober.dart';
import '../speed/speed_runner.dart';

enum Stage {
  updateData, // 1. 更新 CFData（数据源）
  fetchIps, // 2. 获取 IP 列表
  tcpCheck, // 3. TCP 直连检测
  availability, // 4. 安全可用性检测
  speedTest, // 5. 带宽测速
  pushGithub, // 6. 推送到 GitHub
}

enum StageStatus { idle, running, done, fail }

typedef StageCallback = void Function(Stage stage, StageStatus status, [String? detail]);

/// 一键执行流水线（对应旧版 _run_all）。
///
/// 所有网络/IO 依赖通过构造参数注入，便于测试与 Isolate 隔离。
class RunPipeline {
  final AppConfig config;
  final NodeParser parser;
  final NodeSourceService sourceService;
  final GithubPush? github;

  RunPipeline({
    required this.config,
    required this.parser,
    required this.sourceService,
    this.github,
  });

  Future<void> run({
    required StageCallback onStage,
    Future<double?> Function(String ip, int port, Duration timeout)? latencyProbe,
    Future<SpeedResult> Function(String node, String url, Duration timeout, Duration connectTimeout)? speedMeasure,
    String? ipTxtContent, // 预生成内容（测试注入），为空则尝试从 config.outputFile 读取
  }) async {
    // 阶段 1：更新数据源
    onStage(Stage.updateData, StageStatus.running);
    try {
      final nodes = await sourceService.loadAllSources(config);
      onStage(Stage.updateData, StageStatus.done, '节点数: ${nodes.length}');

      // 阶段 2：获取 IP 列表
      onStage(Stage.fetchIps, StageStatus.running);
      onStage(Stage.fetchIps, StageStatus.done, '候选: ${nodes.length}');

      // 阶段 3：TCP 直连检测（用延迟探测近似，超时即失败）
      onStage(Stage.tcpCheck, StageStatus.running);
      final (ordered, tested, connected) = await latencyProbeAll(
        nodes,
        timeout: Duration(milliseconds: (config.timeout * 1000).round()),
        workers: config.maxWorkers,
        probe: latencyProbe,
      );
      final passed = ordered.where((r) => r.latencyMs != null).map((r) => r.node).toList();
      onStage(Stage.tcpCheck, StageStatus.done, '连通: $connected/$tested');

      // 阶段 4：可用性检测（占位：直接沿用连通结果）
      onStage(Stage.availability, StageStatus.running);
      onStage(Stage.availability, StageStatus.done, '可用: ${passed.length}');

      // 阶段 5：带宽测速
      onStage(Stage.speedTest, StageStatus.running);
      final speedResults = await SpeedRunner.runWithRetry(
        passed,
        config,
        measure: speedMeasure,
      );
      final speedMap = {for (final r in speedResults) r.node: r.speedMbps};
      onStage(Stage.speedTest, StageStatus.done, '有速度: ${speedResults.length}');

      // 写出 ip.txt
      final finalNodes = config.useGlobalMode
          ? passed.take(config.globalTopN).toList()
          : passed;
      final outPath = await IpWriter.writeIpTxt(
        finalNodes,
        config.outputFile,
        config,
        speedMap: speedMap,
      );

      // 阶段 6：推送到 GitHub
      onStage(Stage.pushGithub, StageStatus.running);
      if (github != null) {
        final content = ipTxtContent ?? await _readFile(outPath);
        final code = await github!.pushFile(config.outputFile, content,
            message: 'update ${config.outputFile}');
        onStage(Stage.pushGithub, code >= 200 && code < 300 ? StageStatus.done : StageStatus.fail,
            'HTTP $code');
      } else {
        onStage(Stage.pushGithub, StageStatus.done, '跳过(未配置)');
      }
    } catch (e) {
      onStage(Stage.pushGithub, StageStatus.fail, e.toString());
      rethrow;
    }
  }

  Future<String> _readFile(String path) async {
    final f = File(path);
    return f.existsSync() ? f.readAsStringSync() : '';
  }
}
