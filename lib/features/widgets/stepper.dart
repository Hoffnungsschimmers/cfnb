import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/pipeline/run_pipeline.dart';

/// 阶段步骤条（对应旧版 StepperWidget）。
class StageStepper extends StatelessWidget {
  final Map<Stage, StageStatus> status;
  final Stage? current;

  const StageStepper({required this.status, this.current, super.key});

  static const labels = {
    Stage.updateData: '更新数据',
    Stage.fetchIps: '获取IP',
    Stage.tcpCheck: 'TCP检测',
    Stage.availability: '可用性',
    Stage.speedTest: '带宽测速',
    Stage.pushGithub: '推送',
  };

  @override
  Widget build(BuildContext context) {
    final t = AppThemeExt.of(context);
    final ordered = Stage.values;
    return Row(
      children: [
        for (var i = 0; i < ordered.length; i++) ...[
          _Step(
            label: labels[ordered[i]]!,
            status: status[ordered[i]] ?? StageStatus.idle,
            active: current == ordered[i],
          ),
          if (i < ordered.length - 1)
            Expanded(
              child: Container(
                height: 2,
                color: t.border,
                margin: const EdgeInsets.symmetric(horizontal: 4),
              ),
            ),
        ],
      ],
    );
  }
}

class _Step extends StatelessWidget {
  final String label;
  final StageStatus status;
  final bool active;
  const _Step({required this.label, required this.status, this.active = false});

  @override
  Widget build(BuildContext context) {
    final t = AppThemeExt.of(context);
    Color color;
    IconData icon;
    switch (status) {
      case StageStatus.done:
        color = Colors.green;
        icon = Icons.check;
        break;
      case StageStatus.running:
        color = AppTheme.edgeOrange;
        icon = Icons.sync;
        break;
      case StageStatus.fail:
        color = Colors.red;
        icon = Icons.close;
        break;
      case StageStatus.idle:
        color = t.border;
        icon = Icons.circle;
        break;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: status == StageStatus.idle ? t.surface : color,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
          child: Icon(icon, size: 16,
              color: status == StageStatus.idle ? t.textDim : Colors.white),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(
              fontSize: 11,
              color: active ? AppTheme.edgeOrange : t.textDim,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
            )),
      ],
    );
  }
}
