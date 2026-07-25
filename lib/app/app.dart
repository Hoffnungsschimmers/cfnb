import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/results/results_tab.dart';
import '../features/subscriptions/config_tab.dart';
import '../features/subscriptions/run_tab.dart';
import 'motion.dart';
import 'providers.dart';
import 'theme.dart';

final tabProvider = StateProvider<int>((ref) => 0);

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(tabProvider);
    final isWide = MediaQuery.of(context).size.width >= 720;
    final t = AppThemeExt.of(context);
    final pages = const [ConfigTab(), RunTab(), ResultsTab()];

    final appBar = AppBar(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppTheme.edgeOrange,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.cloud_outlined, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          const Flexible(
            child: Text('CF优选', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18), overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      actions: [
        // 主题切换按钮（全局可见）
        IconButton(
          icon: Icon(
            Theme.of(context).brightness == Brightness.dark
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined,
            color: t.textDim,
          ),
          tooltip: Theme.of(context).brightness == Brightness.dark ? '切换浅色' : '切换深色',
          onPressed: () async {
            final current = ref.read(themeModeProvider);
            final next = current == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
            ref.read(themeModeProvider.notifier).state = next;
            // 持久化主题偏好
            final repo = await ref.read(configRepositoryProvider.future);
            await repo.save(repo.current.copyWith(guiTheme: next == ThemeMode.dark ? 'dark' : 'light'));
          },
        ),
        const SizedBox(width: 4),
      ],
    );

    if (isWide) {
      return Scaffold(
        appBar: appBar,
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
            Expanded(
              child: AnimatedSwitcher(
                duration: Motion.durPage,
                switchInCurve: Motion.curveEmphasized,
                switchOutCurve: Motion.curveExit,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.02, 0),
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(key: ValueKey(tab), child: pages[tab]),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: appBar,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: Motion.durPage,
          switchInCurve: Motion.curveEmphasized,
          switchOutCurve: Motion.curveExit,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.02, 0),
                end: Offset.zero,
              ).animate(anim),
              child: child,
            ),
          ),
          child: KeyedSubtree(key: ValueKey(tab), child: pages[tab]),
        ),
      ),
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
