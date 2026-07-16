import 'dart:io';

import 'package:cfnb_app/core/latency/latency_filter.dart';
import 'package:cfnb_app/core/latency/latency_prober.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseEndpoint', () {
    test('parses ipv4', () {
      final r = parseEndpoint('1.2.3.4:443#US');
      expect(r, isNotNull);
      expect(r!.$1, '1.2.3.4');
      expect(r.$2, 443);
    });
    test('parses ipv6', () {
      final r = parseEndpoint('[2001:db8::1]:443#US');
      expect(r!.$1, '2001:db8::1');
      expect(r.$2, 443);
    });
    test('rejects bad port', () {
      expect(parseEndpoint('1.2.3.4:99999#US'), isNull);
      expect(parseEndpoint('notanode'), isNull);
    });
  });

  group('nodeCountry / nodeSource', () {
    test('extracts country and source', () {
      expect(nodeCountry('1.2.3.4:443#JP@CM'), 'JP');
      expect(nodeSource('1.2.3.4:443#JP@CM'), 'CM');
      expect(nodeCountry('1.2.3.4:443'), '');
      expect(nodeSource('1.2.3.4:443#JP'), '');
    });
  });

  group('latencyProbeAll', () {
    test('orders succeeded before failed, ascending latency', () async {
      // 注入假探测：按 ip 末位决定延迟，特定 ip 超时
      Future<double?> fake(String ip, int port, Duration _) async {
        if (ip.endsWith('.9')) return null; // 超时
        final last = int.parse(ip.split('.').last);
        return last.toDouble();
      }
      final nodes = [
        '10.0.0.3:443#US',
        '10.0.0.1:443#US',
        '10.0.0.9:443#US', // 失败
      ];
      final (ordered, tested, connected) = await latencyProbeAll(
        nodes,
        timeout: const Duration(seconds: 2),
        workers: 5,
        probe: fake,
      );
      expect(tested, 3);
      expect(connected, 2);
      expect(ordered.first.latencyMs, 1.0);
      expect(ordered.last.latencyMs, isNull);
    });

    test('respects worker semaphore (no overflow)', () async {
      var concurrent = 0;
      var maxConcurrent = 0;
      Future<double?> fake(String ip, int port, Duration _) async {
        concurrent++;
        maxConcurrent = maxConcurrent < concurrent ? concurrent : maxConcurrent;
        await Future.delayed(const Duration(milliseconds: 10));
        concurrent--;
        return 1.0;
      }
      final nodes = List.generate(20, (i) => '10.0.0.$i:443#US');
      await latencyProbeAll(nodes, timeout: const Duration(seconds: 2), workers: 4, probe: fake);
      expect(maxConcurrent, lessThanOrEqualTo(4));
    });
  });

  group('LatencyFilter.run', () {
    test('writes output and json with topn', () async {
      Future<double?> fake(String ip, int port, Duration _) async {
        if (ip.endsWith('.9')) return null;
        return int.parse(ip.split('.').last).toDouble();
      }
      final dir = await Directory.systemTemp.createTemp('cfnb_lat_');
      final out = '${dir.path}/addressesapi_top.txt';
      final nodes = [
        '10.0.0.5:443#US@CM',
        '10.0.0.2:443#US@CM',
        '10.0.0.9:443#US@CM',
      ];
      final (kept, tested, connected) = await LatencyFilter.run(
        nodes: nodes,
        outputFile: out,
        topN: 2,
        timeout: const Duration(seconds: 2),
        workers: 5,
        nodeSource: {'10.0.0.5:443#US@CM': 'CM'},
        probe: fake,
      );
      expect(tested, 3);
      expect(connected, 2);
      expect(kept.length, 2);
      final content = await File(out).readAsString();
      expect(content, contains('ms'));
      final json = await File('$out.json').readAsString();
      expect(json, contains('"connected":2'));
      await dir.delete(recursive: true);
    });
  });
}
