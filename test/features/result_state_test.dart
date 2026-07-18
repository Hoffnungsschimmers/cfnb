import 'package:cfnb_app/features/results/result_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ResultRow.country', () {
    test('uses nodeCountry (splits at @)', () {
      expect(ResultRow('1.2.3.4:443#US@CM').country, 'US');
      expect(ResultRow('1.2.3.4:443#JP').country, 'JP');
      expect(ResultRow('1.2.3.4:443').country, '');
    });
  });
  group('parseResultLines Q', () {
    test('parses quality score', () {
      final rows = parseResultLines('1.2.3.4:443#US 12.34Mbps 50.00ms Q0.87');
      expect(rows.length, 1);
      expect(rows.first.quality, 0.87);
    });
    test('quality null when absent', () {
      final rows = parseResultLines('1.2.3.4:443#US 12.34Mbps 50.00ms');
      expect(rows.first.quality, isNull);
    });
  });
}
