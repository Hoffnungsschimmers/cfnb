import 'package:cfnb_app/app/providers.dart';
import 'package:cfnb_app/app/theme.dart';
import 'package:cfnb_app/core/config/app_config.dart';
import 'package:cfnb_app/core/logging/app_logger.dart';
import 'package:cfnb_app/core/pipeline/run_pipeline.dart';
import 'package:cfnb_app/features/run/run_page.dart';
import 'package:cfnb_app/features/run/run_state.dart';
import 'package:cfnb_app/features/settings/settings_page.dart';
import 'package:cfnb_app/features/subscriptions/subscriptions_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

AppConfig _cfg() => const AppConfig(
      useGlobalMode: true,
      globalTopN: 30,
      subGenerators: ['默认订阅|sub.example.com', '备用订阅|sub2.example.com'],
    );

Widget _wrap(Widget child, {List<Override> overrides = const []}) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(home: Scaffold(body: child), theme: AppTheme.light()),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('RunPage', () {
    testWidgets('renders stepper, start button and log drawer', (tester) async {
      await tester.pumpWidget(_wrap(const RunPage(),
          overrides: [loggerProvider.overrideWithValue(AppLogger())]));
      await tester.pumpAndSettle();

      expect(find.text('开始优选'), findsOneWidget);
      expect(find.text('运行日志'), findsOneWidget);
      expect(find.text('CF 优选 · 一键执行'), findsOneWidget);
    });

    testWidgets('collapsing the log drawer hides log and shows restore tab',
        (tester) async {
      await tester.pumpWidget(_wrap(const RunPage(),
          overrides: [loggerProvider.overrideWithValue(AppLogger())]));
      await tester.pumpAndSettle();

      expect(find.text('运行日志'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('运行日志'), findsNothing);
      expect(find.text('◀ 日志'), findsOneWidget);
    });

    testWidgets('log lines stream into the LogView', (tester) async {
      final logger = AppLogger();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: LogView(logger: logger)), theme: AppTheme.light()));
      await tester.pump();

      logger.info('hello from test');
      await tester.pumpAndSettle();

      expect(find.text('hello from test'), findsOneWidget);
    });
  });

  group('SettingsPage', () {
    testWidgets('renders config fields from provider', (tester) async {
      await tester.pumpWidget(_wrap(const SettingsPage(),
          overrides: [configProvider.overrideWith((_) async => _cfg())]));
      await tester.pumpAndSettle();

      expect(find.text('启用全局模式'), findsOneWidget);
      expect(find.text('保留节点数 (TOP N)'), findsOneWidget);
      expect(find.text('启用 Cloudflare DNS 更新'), findsOneWidget);

      // 开关依据 useGlobalMode=true 应为开启
      final sw = tester.widget<Switch>(find.byType(Switch).first);
      expect(sw.value, isTrue);
    });
  });

  group('SubscriptionsPage', () {
    testWidgets('renders generator list from config', (tester) async {
      await tester.pumpWidget(_wrap(const SubscriptionsPage(),
          overrides: [configProvider.overrideWith((_) async => _cfg())]));
      await tester.pumpAndSettle();

      expect(find.text('订阅器管理（2）'), findsOneWidget);
      expect(find.text('默认订阅'), findsOneWidget);
      expect(find.text('备用订阅'), findsOneWidget);
    });
  });

  group('RunNotifier', () {
    test('initial state is idle and not running', () {
      final container = ProviderContainer(
          overrides: [loggerProvider.overrideWithValue(AppLogger())]);
      final s = container.read(runProvider);
      expect(s.running, isFalse);
      expect(s.progress, 0);
      expect(s.stages.values.every((e) => e == StageStatus.idle), isTrue);
      container.dispose();
    });
  });
}
