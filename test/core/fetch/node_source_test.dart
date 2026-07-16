import 'dart:io';

import 'package:cfnb_app/core/config/app_config.dart';
import 'package:cfnb_app/core/fetch/node_parser.dart';
import 'package:cfnb_app/core/fetch/node_source.dart';
import 'package:flutter_test/flutter_test.dart';

NodeParser makeParser() => NodeParser(
      cnToCode: {'美国': 'US', '中国': 'CN'},
      alpha3ToAlpha2: {'USA': 'US'},
    );

void main() {
  group('NodeSourceService.fetchAdditionalSource (local file)', () {
    test('reads local file and parses nodes', () async {
      final dir = await Directory.systemTemp.createTemp('cfnb_src_');
      final file = File('${dir.path}/nodes.txt')
        ..writeAsStringSync('1.2.3.4:443#美国\n# comment\n9.9.9.9:443#US\n');
      final svc = NodeSourceService(parser: makeParser());
      final nodes = await svc.fetchAdditionalSource(file.path, const AppConfig());
      expect(nodes, contains('1.2.3.4:443#US'));
      expect(nodes, contains('9.9.9.9:443#US'));
      expect(nodes.length, 2);
      await dir.delete(recursive: true);
    });
  });

  group('NodeSourceService.loadAllSources', () {
    test('merges and dedupes across sources', () async {
      final dir = await Directory.systemTemp.createTemp('cfnb_all_');
      final f1 = File('${dir.path}/a.txt')..writeAsStringSync('1.1.1.1:443#US\n');
      final f2 = File('${dir.path}/b.txt')..writeAsStringSync('1.1.1.1:443#US\n8.8.8.8:443#US\n');
      final cfg = AppConfig(
        additionalSources: [
          SourceConfig(url: f1.path),
          SourceConfig(url: f2.path),
        ],
      );
      final svc = NodeSourceService(parser: makeParser());
      final nodes = await svc.loadAllSources(cfg);
      expect(nodes.length, 2);
      expect(nodes, contains('8.8.8.8:443#US'));
      await dir.delete(recursive: true);
    });
  });
}
