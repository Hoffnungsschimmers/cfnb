import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/results/results_page.dart';
import '../features/run/run_page.dart';
import '../features/settings/settings_page.dart';
import '../features/subscriptions/subscriptions_page.dart';
import '../core/logging/app_logger.dart';
import 'theme.dart';

enum PageKey { run, subs, settings, results }

final pageProvider = StateProvider<PageKey>((ref) => PageKey.run);
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.light);

class AppShell extends ConsumerWidget {
  const AppShell({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(pageProvider);
    final isWide = MediaQuery.of(context).size.width >= 720;

    final content = _pageWidget(page);

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            _Sidebar(ref: ref, current: page),
            Expanded(child: content),
          ],
        ),
      );
    }
    return Scaffold(
      body: content,
      bottomNavigationBar: _BottomNav(ref: ref, current: page),
    );
  }

  Widget _pageWidget(PageKey p) {
    switch (p) {
      case PageKey.run:
        return const RunPage();
      case PageKey.subs:
        return const SubscriptionsPage();
      case PageKey.settings:
        return const SettingsPage();
      case PageKey.results:
        return const ResultsPage();
    }
  }
}

class _Sidebar extends StatelessWidget {
  final WidgetRef ref;
  final PageKey current;
  const _Sidebar({required this.ref, required this.current});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 84,
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF0A0807)
          : const Color(0xFF1A1714),
      child: Column(
        children: [
          const SizedBox(height: 24),
          const Icon(Icons.cloud, color: AppTheme.edgeOrange, size: 28),
          const SizedBox(height: 20),
          for (final item in [
            (PageKey.run, Icons.play_arrow, '运行'),
            (PageKey.subs, Icons.link, '订阅器'),
            (PageKey.settings, Icons.settings, '设置'),
            (PageKey.results, Icons.bar_chart, '结果'),
          ])
            _NavItem(
              icon: item.$2,
              label: item.$3,
              active: current == item.$1,
              onTap: () => ref.read(pageProvider.notifier).state = item.$1,
            ),
          const Spacer(),
          IconButton(
            icon: Icon(
              ref.watch(themeModeProvider) == ThemeMode.dark
                  ? Icons.light_mode
                  : Icons.dark_mode,
              color: Colors.white70,
            ),
            onPressed: () => ref.read(themeModeProvider.notifier).state =
                ref.read(themeModeProvider) == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _NavItem({required this.icon, required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        color: active ? AppTheme.edgeOrange.withValues(alpha: 0.18) : null,
        child: Column(
          children: [
            Icon(icon, color: active ? AppTheme.edgeOrange : Colors.white70),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 11, color: active ? AppTheme.edgeOrange : Colors.white70)),
          ],
        ),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final WidgetRef ref;
  final PageKey current;
  const _BottomNav({required this.ref, required this.current});

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: PageKey.values.indexOf(current),
      onDestinationSelected: (i) => ref.read(pageProvider.notifier).state = PageKey.values[i],
      destinations: const [
        NavigationDestination(icon: Icon(Icons.play_arrow), label: '运行'),
        NavigationDestination(icon: Icon(Icons.link), label: '订阅器'),
        NavigationDestination(icon: Icon(Icons.settings), label: '设置'),
        NavigationDestination(icon: Icon(Icons.bar_chart), label: '结果'),
      ],
    );
  }
}
