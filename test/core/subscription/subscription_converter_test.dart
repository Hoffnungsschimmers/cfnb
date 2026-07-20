import 'dart:convert';

import 'package:cfnb_app/core/config/app_config.dart';
import 'package:cfnb_app/core/net/ip.dart';
import 'package:cfnb_app/core/fetch/node_parser.dart';
import 'package:cfnb_app/core/subscription/subscription_converter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final parser = NodeParser(cnToCode: {'美国': 'US'}, alpha3ToAlpha2: {});

  group('decodeSubscription / resolveSubUrl', () {
    test('returns plaintext links as-is', () {
      const txt = 'vmess://abc\nvless://def';
      expect(decodeSubscription(txt), txt);
    });
    test('decodes base64 subscription', () {
      final b64 = base64UrlEncode(utf8.encode('vmess://abc123'));
      expect(decodeSubscription(b64), contains('vmess://'));
    });
    test('resolves sub:// share link', () {
      final inner = base64UrlEncode(utf8.encode('https://real.example.com/sub'));
      expect(resolveSubUrl('sub://$inner'), 'https://real.example.com/sub');
    });
    test('passes through normal url', () {
      expect(resolveSubUrl('https://x.com/a'), 'https://x.com/a');
    });
  });

  group('generatorFetchUrls', () {
    test('builds fallback urls', () {
      final cfg = AppConfig(subNodeHost: 'h.com', subNodeUuid: 'uuid-1');
      final urls = generatorFetchUrls('sub.example.com', cfg);
      expect(urls.length, 3);
      expect(urls[0], contains('/sub?host=h.com&uuid=uuid-1'));
      expect(urls[1], endsWith('/auto'));
      expect(urls[2], endsWith('/sub?token=auto'));
    });
    test('direct url mode returns as-is', () {
      final urls = generatorFetchUrls('https://sub.x.com/abcdef', const AppConfig());
      expect(urls, ['https://sub.x.com/abcdef']);
    });
  });

  group('collectSubscriptionTasks', () {
    test('node mode collects generators, skips disabled', () {
      final cfg = AppConfig(
        subInputMode: 'node',
        subGenerators: const ['CM|sub.cm.com', 'IDK|sub.idk.com'],
        subDisabledGenerators: const {'IDK'},
      );
      final tasks = collectSubscriptionTasks(cfg);
      expect(tasks.length, 1);
      expect(tasks.first.$1, 'CM');
    });
    test('both mode merges node + url', () {
      final cfg = AppConfig(
        subInputMode: 'both',
        subGenerators: const ['CM|sub.cm.com'],
        subUrls: const ['https://my.sub/abcd'],
      );
      final tasks = collectSubscriptionTasks(cfg);
      expect(tasks.length, 2);
    });
  });

  group('fetchFirstWorking', () {
    test('returns first url that yields nodes, concurrently', () async {
      int callCount = 0;
      Future<String> fetcher(String url) async {
        callCount++;
        if (url.contains('fail')) return '';
        return 'vless://u@host.com:443';
      }
      final urls = ['https://a/fail', 'https://b/fail', 'https://c/ok'];
      final res = await fetchFirstWorking(urls, fetcher);
      expect(res, contains('vless://'));
      expect(callCount, 3); // 并发：全部发起
    });
  });

  group('convertSubscriptions', () {
    test('fetches, parses, resolves, dedups, maps source', () async {
      // 节点链接直接返回（无需抓取）
      Future<String?> fakeResolve(String host) async => host == 'node1.com' ? '1.1.1.1' : '2.2.2.2';

      const sub = 'vless://u@node1.com:443?remarks=%E7%BE%8E%E5%9B%BD#%E7%BE%8E%E5%9B%BD\n'
          'vless://u@node2.com:443#%E7%BE%8E%E5%9B%BD';
      // 用直连 URL 模式注入内容
      // fetchSingle 对节点链接原样返回；但这里是 https url，会调用 fakeFetch(url)
      // 让它返回订阅明文：
      Future<String> fetchWithBody(String url) async => sub;

      final (nodes, src) = await convertSubscriptions(
        AppConfig(subInputMode: 'url', subUrls: const ['https://my.sub/abcd']),
        fetch: fetchWithBody,
        resolve: fakeResolve,
        parser: parser,
      );
      expect(nodes.length, 2);
      expect(nodes.any((n) => n.startsWith('1.1.1.1:443#US')), isTrue);
      expect(nodes.any((n) => n.startsWith('2.2.2.2:443#US')), isTrue);
      // 按 IP:port#cc 去重：两个不同 host 解析到同一 IP 且有相同国家码时只留一个
      final cfg2 = AppConfig(subInputMode: 'url', subUrls: const ['https://my.sub/abcd']);
      Future<String?> dupResolve(String host) async => '9.9.9.9';
      final (nodes2, _) = await convertSubscriptions(
        cfg2,
        fetch: fetchWithBody,
        resolve: dupResolve,
        parser: parser,
      );
      expect(nodes2.length, 1);
    });
  });

  group('concurrency (task-2)', () {
    test('sources fetched concurrently, total time < sum', () async {
      const aContent =
          'vless://u@1.1.1.1:443#US\nvless://u@1.1.1.1:8443#US';
      const bContent =
          'vless://u@1.1.1.2:443#美国\nvless://u@1.1.1.2:8443#美国';

      Future<String> fetch(String url) async {
        if (url.contains('nodeA.com')) {
          await Future.delayed(const Duration(milliseconds: 200));
          return aContent;
        }
        if (url.contains('nodeB.com')) {
          await Future.delayed(const Duration(milliseconds: 500));
          return bContent;
        }
        return '';
      }

      Future<String?> resolve(String host) async => isIp(host) ? host : null;

      final cfg = AppConfig(
        subInputMode: 'node',
        subGenerators: const ['A|nodeA.com', 'B|nodeB.com'],
        subResolveDomain: true,
        subResolveWorkers: 4,
      );

      final sw = Stopwatch()..start();
      final (nodes, src) = await convertSubscriptions(
        cfg,
        fetch: fetch,
        resolve: resolve,
        parser: parser,
      );
      final elapsed = sw.elapsedMilliseconds;

      // 并发：总耗时接近 max(200,500)=500，远低于累加 700。
      expect(elapsed, lessThan(700),
          reason: 'expected concurrent fetch, got $elapsed ms');

      // 去重按 ip:port#cc：A、B 两源节点都在；同 IP 不同端口都保留。
      expect(nodes.length, 4);
      expect(src.values.contains('A'), isTrue);
      expect(src.values.contains('B'), isTrue);
      expect(nodes.any((n) => n == '1.1.1.1:443#US'), isTrue);
      expect(nodes.any((n) => n == '1.1.1.1:8443#US'), isTrue);
      expect(nodes.any((n) => n == '1.1.1.2:443#US'), isTrue);
      expect(nodes.any((n) => n == '1.1.1.2:8443#US'), isTrue);
    });

    test('fetchFirstWorking returns first winner without waiting for slowest',
        () async {
      const fast = 'vless://fast@1.2.3.4:443#US';
      const slow = 'vless://slow@5.6.7.8:443#JP';
      Future<String> fetch(String url) async {
        if (url.contains('fast')) {
          await Future.delayed(const Duration(milliseconds: 50));
          return fast;
        }
        await Future.delayed(const Duration(milliseconds: 500));
        return slow;
      }

      final res = await fetchFirstWorking(
        ['https://x/fast', 'https://x/slow'],
        fetch,
      );
      expect(res, fast);
    });

    test('fetchFirstWorking empty list returns empty string', () async {
      final res = await fetchFirstWorking([], (u) async => '');
      expect(res, '');
    });
  });
}
