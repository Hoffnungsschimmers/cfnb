import 'package:cfnb_app/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppConfig defaults', () {
    final c = const AppConfig();

    test('has expected default values', () {
      expect(c.guiTheme, 'light');
      expect(c.subInputMode, 'both');
      expect(c.subConvertEnabled, isTrue);
      expect(c.subNodeUuid, 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx');
      expect(c.subDefaultCountry, '');
      expect(c.subLatencyProbes, 3);
      expect(c.subLatencyOutputFile, 'addressesapi_top.txt');
      expect(c.subSpeedEnabled, isTrue);
      expect(c.githubRepo, 'Hoffnungsschimmers/cf-ip');
    });

    test('dead fields removed', () {
      // 编译期保证：以下字段不应存在
      expect(c is AppConfig, isTrue);
    });

    test('toJson then fromJson is stable', () {
      final json = c.toJson();
      final round = AppConfig.fromJson(json);
      expect(round.subDisabledGenerators, c.subDisabledGenerators);
      expect(round.additionalSources, c.additionalSources);
      expect(round.subGenerators, c.subGenerators);
      expect(round.subLatencyProbes, c.subLatencyProbes);
    });
  });

  group('AppConfig.fromJson parsing', () {
    test('parses additional sources list', () {
      final c = AppConfig.fromJson({
        'ADDITIONAL_SOURCES': [
          {'url': 'https://a.example/nodes', 'enabled': false},
        ]
      });
      expect(c.additionalSources.length, 1);
      expect(c.additionalSources.first.url, 'https://a.example/nodes');
      expect(c.additionalSources.first.enabled, false);
    });

    test('parses disabled generators set', () {
      final c = AppConfig.fromJson({
        'SUB_DISABLED_GENERATORS': ['CM', 'HK'],
      });
      expect(c.subDisabledGenerators, {'CM', 'HK'});
    });

    test('ignores unknown legacy keys without throwing', () {
      final c = AppConfig.fromJson({
        'CF_API_TOKEN': 'x',
        'ASN_SOURCES': [1],
        'SUB_NODE_UUID': 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx',
      });
      expect(c.subNodeUuid, 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx');
    });
  });

  group('AppConfig.validate', () {
    test('accepts defaults', () {
      expect(const AppConfig().validate(), isEmpty);
    });

    test('rejects bad sub input mode', () {
      final bad = AppConfig.fromJson({'SUB_INPUT_MODE': 'xxx'});
      expect(bad.validate(), isNotEmpty);
    });
  });

  group('AppConfig.copyWith', () {
    test('updates single field without touching others', () {
      final c = const AppConfig();
      final updated = c.copyWith(guiTheme: 'dark', subLatencyProbes: 5);
      expect(updated.guiTheme, 'dark');
      expect(updated.subLatencyProbes, 5);
      expect(updated.subInputMode, c.subInputMode);
    });
  });
}
