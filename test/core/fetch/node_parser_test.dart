import 'package:cfnb_app/core/fetch/node_parser.dart';
import 'package:flutter_test/flutter_test.dart';

NodeParser makeParser() => NodeParser(
      cnToCode: {
        '美国': 'US',
        '中国': 'CN',
        '日本': 'JP',
        '德国': 'DE',
      },
      alpha3ToAlpha2: {
        'USA': 'US',
        'DEU': 'DE',
        'JPN': 'JP',
      },
    );

void main() {
  final parser = makeParser();

  group('extractCountryCode', () {
    test('matches alpha2 directly', () {
      expect(parser.extractCountryCode('US'), 'US');
      expect(parser.extractCountryCode('JP'), 'JP');
    });
    test('matches alpha3', () {
      expect(parser.extractCountryCode('USA'), 'US');
      expect(parser.extractCountryCode('DEU'), 'DE');
    });
    test('matches chinese name', () {
      expect(parser.extractCountryCode('美国'), 'US');
      expect(parser.extractCountryCode('日本'), 'JP');
    });
    test('returns null when unknown', () {
      expect(parser.extractCountryCode('???'), isNull);
    });
  });

  group('parseTextNodes', () {
    test('parses ip:port#label with country', () {
      final nodes = parser.parseTextNodes('1.2.3.4:443#美国\n');
      expect(nodes, ['1.2.3.4:443#US']);
    });
    test('adds default port 443 for bare ip', () {
      final nodes = parser.parseTextNodes('1.2.3.4#日本');
      expect(nodes, ['1.2.3.4:443#JP']);
    });
    test('skips nodes without recognized country', () {
      final nodes = parser.parseTextNodes('1.2.3.4:443#未知');
      expect(nodes, isEmpty);
    });
    test('ignores comment lines', () {
      final nodes = parser.parseTextNodes('#1.2.3.4:443#US');
      expect(nodes, isEmpty);
    });
  });

  group('parseAdaptive', () {
    test('parses JSON list of nodes', () {
      final text = '[{"ip":"1.1.1.1","port":443,"country":"US"}]';
      final nodes = parser.parseAdaptive(text);
      expect(nodes, ['1.1.1.1:443#US']);
    });
    test('falls back to text', () {
      final nodes = parser.parseAdaptive('9.9.9.9:443#DE');
      expect(nodes, ['9.9.9.9:443#DE']);
    });
  });

  group('parseRipePrefixes', () {
    test('filters by ip version', () {
      final payload = {
        'data': {
          'prefixes': [
            {'prefix': '1.0.0.0/24'},
            {'prefix': '2001:db8::/32'},
          ]
        }
      };
      final v4 = parser.parseRipePrefixes(payload, false);
      expect(v4, ['1.0.0.0/24']);
      final v6 = parser.parseRipePrefixes(payload, true);
      expect(v6, ['2001:db8::/32']);
    });
  });

  group('expandPrefixesToNodes', () {
    test('expands small cidr', () {
      final nodes = parser.expandPrefixesToNodes(['192.0.2.0/30'], 100, 443, 'US');
      expect(nodes.length, 2);
      expect(nodes.first, '192.0.2.1:443#US');
    });
    test('caps to max ips for large cidr', () {
      final nodes = parser.expandPrefixesToNodes(['10.0.0.0/8'], 50, 443, 'US');
      expect(nodes.length, 50);
    });
  });
}
