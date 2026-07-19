import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/results/results_tab.dart';
import '../features/subscriptions/config_tab.dart';
import '../features/subscriptions/run_tab.dart';

final tabProvider = StateProvider<int>((ref) => 0);
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.light);

class AppShell extends ConsumerWidget {
  const AppShell({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(tabProvider);
    final isWide = MediaQuery.of(context).size.width >= 720;
    final pages = const [ConfigTab(), RunTab(), ResultsTab()];

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: tab,
              onDestinationSelected: (i) => ref.read(tabProvider.notifier).state = i,
              labelType: NavigationRailLabelType.all,
              destinations: const [
                NavigationRailDestination(icon: Icon(Icons.tune), label: Text('配置')),
                NavigationRailDestination(icon: Icon(Icons.play_arrow), label: Text('运行')),
                NavigationRailDestination(icon: Icon(Icons.bar_chart), label: Text('结果')),
              ],
            ),
            Expanded(child: pages[tab]),
          ],
        ),
      );
    }
    return Scaffold(
      body: pages[tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => ref.read(tabProvider.notifier).state = i,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.tune), label: '配置'),
          NavigationDestination(icon: Icon(Icons.play_arrow), label: '运行'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: '结果'),
        ],
      ),
    );
  }
}
