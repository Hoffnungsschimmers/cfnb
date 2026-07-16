import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/fetch/node_source.dart';
import '../../core/github/github_push.dart';
import '../../core/latency/latency_prober.dart';
import '../../core/pipeline/run_pipeline.dart';
import '../../core/speed/speed_prober.dart';
import '../../app/providers.dart';
import '../../features/widgets/stepper.dart';

/// 运行页状态：阶段状态、进度、是否运行中。
class RunState {
  final Map<Stage, StageStatus> stages;
  final bool running;
  final double progress;
  RunState({required this.stages, this.running = false, this.progress = 0});

  RunState copyWith({Map<Stage, StageStatus>? stages, bool? running, double? progress}) =>
      RunState(
        stages: stages ?? this.stages,
        running: running ?? this.running,
        progress: progress ?? this.progress,
      );
}

class RunNotifier extends StateNotifier<RunState> {
  final Ref ref;
  RunNotifier(this.ref)
      : super(RunState(
          stages: {for (final s in Stage.values) s: StageStatus.idle},
        ));

  Future<void> start() async {
    final repo = await ref.read(configRepositoryProvider.future);
    final parser = await ref.read(nodeParserProvider.future);
    final logger = ref.read(loggerProvider);
    final cfg = repo.current;

    final github = cfg.cfEnabled
        ? GithubPush(token: cfg.cfApiToken, repo: 'Hoffnungsschimmers/cf-ip')
        : null;

    final source = NodeSourceService(parser: parser);
    final pipeline = RunPipeline(config: cfg, parser: parser, sourceService: source, github: github);

    state = state.copyWith(
      running: true,
      stages: {for (final s in Stage.values) s: StageStatus.idle},
      progress: 0,
    );

    logger.info('开始一键执行（6 阶段）');

    void onStage(Stage s, StageStatus st, [String? detail]) {
      final next = {...state.stages};
      next[s] = st;
      final done = next.values.where((e) => e == StageStatus.done).length;
      state = state.copyWith(stages: next, progress: done / Stage.values.length);
      if (detail != null) logger.info('[${_stageName(s)}] $detail');
    }

    try {
      await pipeline.run(
        onStage: onStage,
        latencyProbe: measureLatency,
        speedMeasure: measureBandwidth,
      );
      logger.info('全部阶段执行完成');
    } catch (e) {
      logger.error(e.toString());
    } finally {
      state = state.copyWith(running: false);
    }
  }

  void stop() {
    // 简化：置为停止态（真实实现需可取消的 token）
    state = state.copyWith(running: false);
  }
}

String _stageName(Stage s) => StageStepper.labels[s] ?? s.name;

final runProvider = StateNotifierProvider<RunNotifier, RunState>((ref) => RunNotifier(ref));
