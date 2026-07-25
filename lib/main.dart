import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/motion.dart';
import 'app/providers.dart';
import 'app/theme.dart';

void main() {
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);

    // 首次加载：从持久化配置读取主题偏好
    ref.listen(configProvider, (_, next) {
      next.whenData((cfg) {
        final ThemeMode initial = switch (cfg.guiTheme) {
          'dark' => ThemeMode.dark,
          'system' => ThemeMode.system,
          _ => ThemeMode.light,
        };
        if (ref.read(themeModeProvider) != initial) {
          ref.read(themeModeProvider.notifier).state = initial;
        }
      });
    });

    return MaterialApp(
      title: 'CF优选工具',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: mode,
      // 主题亮度切换过渡：默认 200ms 硬切拉到强调过渡更明显。
      themeAnimationDuration: Motion.durTheme,
      home: PopScope(
        canPop: true,
        child: const AppShell(),
      ),
    );
  }
}
