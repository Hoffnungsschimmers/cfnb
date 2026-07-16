import 'package:cfnb_app/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppConfig defaults', () {
    final c = const AppConfig();

    test('has expected default values', () {
      expect(c.globalTopN, 15);
      expect(c.timeout, 2.0);
      expect(c.preFilterPorts, [443]);
      expect(c.blockedCountries, contains('CN'));
      expect(c.guiTheme, 'light');
      expect(c.subInputMode, 'both');
      expect(c.dnsRecordType, 'TXT');
      expect(c.outputFile, 'ip.txt');
    });

    test('toJson then fromJson is stable', () {
      final json = c.toJson();
      final round = AppConfig.fromJson(json);
      expect(round.globalTopN, c.globalTopN);
      expect(round.blockedCountries, c.blockedCountries);
      expect(round.subDisabledGenerators, c.subDisabledGenerators);
      expect(round.additionalSources, isEmpty);
    });
  });

  group('AppConfig.fromJson parsing', () {
    test('parses comma string ports into int list', () {
      final c = AppConfig.fromJson({'PRE_FILTER_PORTS': '443,2053'});
      expect(c.preFilterPorts, [443, 2053]);
    });

    test('parses ASN list from list', () {
      final c = AppConfig.fromJson({'ASN_SOURCES': [13335, 209242]});
      expect(c.asnSources, [13335, 209242]);
    });

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
  });

  group('AppConfig.validate', () {
    test('accepts defaults', () {
      expect(const AppConfig().validate(), isEmpty);
    });

    test('rejects bad risk level', () {
      final bad = AppConfig.fromJson({'DNS_IP_RISK_MAX_LEVEL': '未知级别'});
      expect(bad.validate(), isNotEmpty);
    });

    test('rejects bad dns record type', () {
      final bad = AppConfig.fromJson({'DNS_RECORD_TYPE': 'CNAME'});
      expect(bad.validate(), contains(anyOf(contains('A 或 TXT'))));
    });

    test('rejects bad sub input mode', () {
      final bad = AppConfig.fromJson({'SUB_INPUT_MODE': 'xxx'});
      expect(bad.validate(), isNotEmpty);
    });

    test('rejects non-2-letter country', () {
      final bad = AppConfig.fromJson({'ASN_SOURCE_COUNTRY': 'USA'});
      expect(bad.validate(), isNotEmpty);
    });
  });

  group('AppConfig.copyWith', () {
    test('updates single field without touching others', () {
      final c = const AppConfig();
      final updated = c.copyWith(guiTheme: 'dark', globalTopN: 30);
      expect(updated.guiTheme, 'dark');
      expect(updated.globalTopN, 30);
      expect(updated.timeout, c.timeout);
      expect(updated.blockedCountries, c.blockedCountries);
    });
  });
}
