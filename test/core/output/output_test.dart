import 'dart:io';

import 'package:cfnb_app/core/config/app_config.dart';
import 'package:cfnb_app/core/output/ip_writer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IpWriter.writeIpTxt', () {
    test('writes nodes with bandwidth and latency', () async {
      final dir = await Directory.systemTemp.createTemp('cfnb_out_');
      final out = '${dir.path}/ip.txt';
      final nodes = ['1.1.1.1:443#US', '8.8.8.8:443#US'];
      await IpWriter.writeIpTxt(
        nodes,
        out,
        const AppConfig(),
        speedMap: {'1.1.1.1:443#US': 12.34},
        latencyMap: {'1.1.1.1:443#US': 0.05},
      );
      final content = await File(out).readAsString();
      expect(content, contains('1.1.1.1:443#US 12.34 Mbps 50.00 ms'));
      expect(content, contains('8.8.8.8:443#US'));
      await dir.delete(recursive: true);
    });

    test('honors ad header/footer', () async {
      final dir = await Directory.systemTemp.createTemp('cfnb_out2_');
      final out = '${dir.path}/ip.txt';
      final cfg = const AppConfig(
        adHeaderEnabled: true,
        adFooterEnabled: true,
        adHeaderLines: ['# HEAD'],
        adFooterLines: ['# FOOT'],
      );
      await IpWriter.writeIpTxt(['1.1.1.1:443#US'], out, cfg);
      final content = await File(out).readAsString();
      expect(content, startsWith('# HEAD'));
      expect(content, contains('# FOOT'));
      await dir.delete(recursive: true);
    });
  });

  group('Summary', () {
    test('counts speed results', () {
      final s = Summary(
        candidatesCount: 100,
        tcpPassed: 50,
        availabilityPassed: 40,
        speedResults: [('a', 10.0), ('b', 0.0)],
        finalSelected: ['a', 'b'],
      );
      expect(s.speedCount, 1);
      expect(s.toString(), contains('最终选择：2 个节点'));
    });
  });
}
