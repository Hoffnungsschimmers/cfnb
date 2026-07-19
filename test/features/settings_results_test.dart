import 'package:cfnb_app/features/results/result_state.dart';
import 'package:cfnb_app/features/settings/settings_fields.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseResultLines', () {
    test('parses ip.txt with speed and latency', () {
      const text = '# header\n'
          '1.1.1.1:443#US 120.50 Mbps 30.10 ms\n'
          '2.2.2.2:443#JP 9.80 Mbps 62.10 ms\n';
      final rows = parseResultLines(text);
      expect(rows.length, 2);
      expect(rows[0].ipPort, '1.1.1.1:443');
      expect(rows[0].country, 'US');
      expect(rows[0].latency, '30.10 ms');
    });
    test('parses plain node lines (subscription output)', () {
      const text = '1.1.1.1:443#US\n2.2.2.2:443#JP';
      final rows = parseResultLines(text);
      expect(rows.length, 2);
      expect(rows[0].latency, isNull);
      expect(rows[1].country, 'JP');
    });
  });

  group('settingsFields', () {
    test('covers live SETTINGS_FIELDS keys', () {
      final keys = settingsFields.map((f) => f.key).toSet();
      for (final k in const [
        'SUB_CONVERT_ENABLED', 'SUB_GENERATORS', 'SUB_URLS',
        'SUB_LATENCY_MAX_MS', 'SUB_LATENCY_PROBES', 'SUB_LATENCY_SNI',
        'SUB_QUALITY_LATENCY_WEIGHT', 'SUB_SPEED_ENABLED', 'SUB_SPEED_SIZE_MB',
        'GITHUB_REPO', 'GITHUB_BRANCH', 'GUI_THEME',
      ]) {
        expect(keys.contains(k), isTrue, reason: k);
      }
      // 死字段已移除
      for (final k in const [
        'PRE_FILTER_PORT_ENABLED', 'TCP_PROBES', 'TEST_AVAILABILITY',
        'BANDWIDTH_WORKERS', 'USE_GLOBAL_MODE', 'GLOBAL_TOP_N',
        'QUALITY_SPEED_WEIGHT', 'CF_ENABLED', 'CF_API_TOKEN',
        'AUTO_SCHEDULE_ENABLED', 'ASN_SOURCES',
      ]) {
        expect(keys.contains(k), isFalse, reason: k);
      }
    });
    test('includes github + theme sections', () {
      final keys = settingsFields.map((f) => f.key).toSet();
      expect(keys.contains('GITHUB_REPO'), isTrue);
      expect(keys.contains('GITHUB_BRANCH'), isTrue);
      expect(keys.contains('GUI_THEME'), isTrue);
    });
    test('normalizeDraft converts sources text to list', () {
      final draft = {'ADDITIONAL_SOURCES': 'https://a.com\nhttps://b.com\n'};
      final out = normalizeDraft(draft);
      expect(out['ADDITIONAL_SOURCES'], isA<List>());
      expect((out['ADDITIONAL_SOURCES'] as List).length, 2);
    });
  });
}
