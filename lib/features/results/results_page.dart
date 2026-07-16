import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../widgets/common.dart';

class ResultsPage extends ConsumerWidget {
  const ResultsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppThemeExt.of(context);
    // 演示数据（后续接 pipeline 输出）
    final rows = [
      ('1.2.3.4:443#US', '12.34 Mbps', '50.00 ms'),
      ('5.6.7.8:443#JP', '9.80 Mbps', '62.10 ms'),
      ('9.9.9.9:443#DE', '8.10 Mbps', '70.20 ms'),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          sectionTitle(context, '优选结果'),
          const SizedBox(height: 12),
          card(
            context,
            padding: EdgeInsets.zero,
            child: Table(
              columnWidths: const {
                0: FlexColumnWidth(3),
                1: FlexColumnWidth(2),
                2: FlexColumnWidth(2),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(color: t.surfaceHover),
                  children: [
                    _th(context, '节点'),
                    _th(context, '带宽'),
                    _th(context, '延迟'),
                  ],
                ),
                for (final r in rows)
                  TableRow(
                    children: [
                      _td(context, r.$1),
                      _td(context, r.$2),
                      _td(context, r.$3),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _th(BuildContext context, String s) {
    final t = AppThemeExt.of(context);
    return Padding(padding: const EdgeInsets.all(12), child: Text(s, style: TextStyle(fontWeight: FontWeight.bold, color: t.textDim)));
  }

  Widget _td(BuildContext context, String s) {
    final t = AppThemeExt.of(context);
    return Padding(padding: const EdgeInsets.all(12), child: Text(s, style: TextStyle(color: t.text, fontFamily: 'Consolas')));
  }
}
