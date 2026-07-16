import 'package:cfnb_app/core/config/app_config.dart';
import 'package:cfnb_app/core/speed/speed_prober.dart';
import 'package:cfnb_app/core/speed/speed_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('measureBandwidth (logic via injected measure)', () {
    test('runSpeedPass measures all candidates', () async {
      Future<SpeedResult> fake(String node, String url, Duration t, Duration ct) async {
        return SpeedResult(node, 10.0);
      }
      final nodes = ['10.0.0.1:443#US', '10.0.0.2:443#US'];
      final res = await runSpeedPass(nodes, 'http://x', const Duration(seconds: 4),
          const Duration(seconds: 2), 5, measure: fake);
      expect(res.length, 2);
      expect(res.values.every((v) => v == 10.0), isTrue);
    });

    test('runSpeedPass respects workers', () async {
      var concurrent = 0;
      var maxC = 0;
      Future<SpeedResult> fake(String node, String url, Duration t, Duration ct) async {
        concurrent++;
        maxC = maxC < concurrent ? concurrent : maxC;
        await Future.delayed(const Duration(milliseconds: 10));
        concurrent--;
        return SpeedResult(node, 1.0);
      }
      final nodes = List.generate(20, (i) => '10.0.0.$i:443#US');
      await runSpeedPass(nodes, 'http://x', const Duration(seconds: 4),
          const Duration(seconds: 2), 4, measure: fake);
      expect(maxC, lessThanOrEqualTo(4));
    });
  });

  group('SpeedRunner.runMultiPass', () {
    test('funnel: probe then refine, sorted desc', () async {
      Future<SpeedResult> fake(String node, String url, Duration t, Duration ct) async {
        // 探速 url 含 262144，精测含 1048576
        final isRefine = url.contains('1048576');
        final last = int.parse(node.split('.').last.split(':').first);
        final speed = isRefine ? last * 2.0 : last.toDouble();
        return SpeedResult(node, speed);
      }
      final nodes = ['10.0.0.3:443#US', '10.0.0.1:443#US', '10.0.0.2:443#US'];
      final results = await SpeedRunner.runMultiPass(nodes, const AppConfig(), measure: fake);
      // 精测覆盖全部（<=300），速度=last*2
      expect(results.first.node, '10.0.0.3:443#US');
      expect(results.first.speedMbps, 6.0);
    });

    test('returns empty when no speed', () async {
      Future<SpeedResult> fake(String node, String url, Duration t, Duration ct) async {
        return SpeedResult(node, 0.0);
      }
      final nodes = ['10.0.0.1:443#US'];
      final results = await SpeedRunner.runMultiPass(nodes, const AppConfig(), measure: fake);
      expect(results, isEmpty);
    });
  });
}
