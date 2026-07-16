import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../app/providers.dart';
import '../../core/logging/app_logger.dart';
import '../../core/pipeline/run_pipeline.dart';
import '../widgets/common.dart';
import '../widgets/stepper.dart';
import 'run_state.dart';

class RunPage extends ConsumerStatefulWidget {
  const RunPage({super.key});
  @override
  ConsumerState<RunPage> createState() => _RunPageState();
}

class _RunPageState extends ConsumerState<RunPage> {
  double _logWidth = 320;
  bool _logCollapsed = false;
  final double _minW = 200;
  final double _maxW = 560;

  @override
  Widget build(BuildContext context) {
    final t = AppThemeExt.of(context);
    final state = ref.watch(runProvider);
    final logger = ref.watch(loggerProvider);

    return Row(
      children: [
        // 主区域
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                sectionTitle(context, 'CF 优选 · 一键执行'),
                const SizedBox(height: 12),
                card(
                  context,
                  child: Column(
                    children: [
                      StageStepper(
                        status: state.stages,
                        current: state.running
                            ? state.stages.entries
                                .firstWhere((e) => e.value == StageStatus.running,
                                    orElse: () => MapEntry(Stage.updateData, StageStatus.idle))
                                .key
                            : null,
                      ),
                      const SizedBox(height: 14),
                      appProgress(value: state.progress),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: AppButton(
                              state.running ? '执行中…' : '开始优选',
                              icon: Icons.play_arrow,
                              onPressed: state.running ? null : () => ref.read(runProvider.notifier).start(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          AppButton(
                            state.running ? '停止' : '重置',
                            icon: Icons.stop,
                            primary: false,
                            onPressed: () {},
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                // 指标卡
                Row(
                  children: [
                    Expanded(
                      child: _metric(context, '进度',
                          '${(state.progress * 100).toInt()}%', Icons.show_chart),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _metric(context, '已完成阶段',
                          '${state.stages.values.where((e) => e == StageStatus.done).length}/${Stage.values.length}',
                          Icons.check_circle),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _metric(context, '状态',
                          state.running ? '运行中' : '就绪', Icons.circle),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                card(
                  context,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      sectionTitle(context, '测速曲线（规划中）'),
                      const SizedBox(height: 8),
                      Container(
                        height: 140,
                        decoration: BoxDecoration(
                          color: t.bg,
                          borderRadius: t.radius,
                          border: Border.all(color: t.border),
                        ),
                        alignment: Alignment.center,
                        child: Text('带宽测速曲线将在此显示', style: TextStyle(color: t.textDim)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // 拖拽手柄
        if (!_logCollapsed)
          GestureDetector(
            onPanUpdate: (d) {
              setState(() {
                _logWidth = (_logWidth - d.delta.dx).clamp(_minW, _maxW);
              });
            },
            child: Container(width: 5, color: t.border, child: const Icon(Icons.drag_handle, size: 14)),
          ),
        // 日志抽屉
        if (!_logCollapsed)
          Container(
            width: _logWidth,
            decoration: BoxDecoration(
              color: t.logBg,
              border: Border(left: BorderSide(color: t.border)),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: t.border)),
                  ),
                  child: Row(
                    children: [
                      Text('运行日志', style: TextStyle(color: t.logFg, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      IconButton(
                        icon: Icon(Icons.close, size: 18, color: t.textDim),
                        onPressed: () => setState(() => _logCollapsed = true),
                        tooltip: '隐藏日志',
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: LogView(logger: logger),
                ),
              ],
            ),
          ),
        // 折叠后恢复按钮
        if (_logCollapsed)
          GestureDetector(
            onTap: () => setState(() => _logCollapsed = false),
            child: Container(
              width: 22,
              color: t.surface,
              child: RotatedBox(
                quarterTurns: 3,
                child: Center(
                  child: Text('◀ 日志', style: TextStyle(color: t.textDim, fontSize: 12)),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _metric(BuildContext context, String title, String value, IconData icon) {
    final t = AppThemeExt.of(context);
    return card(
      context,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.edgeOrange),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 11, color: t.textDim)),
              Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}

/// 日志视图：订阅 AppLogger 流，节流批量刷新。
class LogView extends StatefulWidget {
  final AppLogger logger;
  const LogView({required this.logger, super.key});
  @override
  State<LogView> createState() => _LogViewState();
}

class _LogViewState extends State<LogView> {
  final List<String> _lines = [];
  final ScrollController _sc = ScrollController();

  @override
  void initState() {
    super.initState();
    _lines.addAll(widget.logger.snapshot);
    widget.logger.stream.listen((line) {
      _lines.add(line);
      if (_lines.length > 2000) _lines.removeAt(0);
      if (mounted) setState(() {});
      _sc.jumpTo(_sc.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeExt.of(context);
    return ListView.builder(
      controller: _sc,
      padding: const EdgeInsets.all(8),
      itemCount: _lines.length,
      itemBuilder: (_, i) => Text(
        _lines[i],
        style: TextStyle(fontFamily: 'Consolas', fontSize: 12, color: t.logFg),
      ),
    );
  }
}
