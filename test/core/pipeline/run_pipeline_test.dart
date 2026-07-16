import 'package:cfnb_app/core/config/app_config.dart';
import 'package:cfnb_app/core/fetch/node_parser.dart';
import 'package:cfnb_app/core/fetch/node_source.dart';
import 'package:cfnb_app/core/github/github_push.dart';
import 'package:cfnb_app/core/pipeline/run_pipeline.dart';
import 'package:cfnb_app/core/speed/speed_prober.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('RunPipeline runs all 6 stages end to end', () async {
    final parser = NodeParser(cnToCode: {'美国': 'US'}, alpha3ToAlpha2: {});
    // 注入假的 loadAllSources 通过子类
    final fakeSource = _FakeSource(parser);

    final stages = <Stage, StageStatus>{};
    StageCallback cb = (s, st, [d]) => stages[s] = st;

    Future<double?> fakeLat(String ip, int port, Duration t) async => 10.0;
    Future<SpeedResult> fakeSpeed(String node, String url, Duration t, Duration ct) async =>
        SpeedResult(node, 50.0);

    var pushed = false;
    Future<Response> fakeGh(RequestOptions o) async {
      if (o.method == 'GET') {
        throw DioException(requestOptions: o, response: Response(statusCode: 404, requestOptions: o));
      }
      pushed = true;
      return Response(statusCode: 201, requestOptions: o, data: {});
    }
    final gh = GithubPush(token: 't', repo: 'o/cf-ip', sender: fakeGh);

    final pipeline = RunPipeline(config: const AppConfig(), parser: parser, sourceService: fakeSource, github: gh);
    await pipeline.run(onStage: cb, latencyProbe: fakeLat, speedMeasure: fakeSpeed);

    expect(stages[Stage.updateData], StageStatus.done);
    expect(stages[Stage.fetchIps], StageStatus.done);
    expect(stages[Stage.tcpCheck], StageStatus.done);
    expect(stages[Stage.availability], StageStatus.done);
    expect(stages[Stage.speedTest], StageStatus.done);
    expect(stages[Stage.pushGithub], StageStatus.done);
    expect(pushed, isTrue);
  });
}

class _FakeSource extends NodeSourceService {
  _FakeSource(NodeParser parser) : super(parser: parser, dio: Dio());
  @override
  Future<List<String>> loadAllSources(AppConfig config,
      {bool skipFetch = false, String? cachedFile}) async {
    return ['1.2.3.4:443#US', '5.6.7.8:443#US'];
  }
}
