import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../subscriptions/subscriptions_state.dart';
import '../widgets/common.dart';

class RunTab extends ConsumerWidget {
  const RunTab({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final run = ref.watch(subProvider);
    final subLogger = ref.watch(subLoggerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              AppButton('订阅IP', icon: Icons.cloud_download,
                  onPressed: run.running ? null : () => ref.read(subProvider.notifier).runSubscription()),
              AppButton('延迟优选', icon: Icons.speed, primary: false,
                  onPressed: run.running ? null : () => ref.read(subProvider.notifier).runLatency()),
            ],
          ),
        ),
        Expanded(child: LogView(logger: subLogger)),
      ],
    );
  }
}
