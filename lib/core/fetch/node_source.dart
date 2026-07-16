import 'dart:io';

import 'package:dio/dio.dart';

import '../config/app_config.dart';
import 'node_parser.dart';

/// 节点数据源拉取服务（对应旧版 fetcher 的网络函数）。
///
/// 纯 Dart 实现，使用 dio 做带超时/重试的 HTTP 请求。所有函数不依赖 UI，
/// 可在 Isolate 中运行。国家代码映射通过 [NodeParser] 注入。
class NodeSourceService {
  final NodeParser parser;
  final Dio dio;

  NodeSourceService({required this.parser, Dio? dio})
      : dio = dio ??
            Dio(BaseOptions(
              followRedirects: true,
              receiveTimeout: const Duration(seconds: 30),
            ));

  /// 拉取单个附加源（URL 或本地文件），返回标准节点列表。
  Future<List<String>> fetchAdditionalSource(String url, AppConfig config) async {
    if (url.isEmpty) return [];

    if (await File(url).exists()) {
      try {
        final text = await File(url).readAsString();
        return parser.parseAdaptive(text);
      } on FileSystemException {
        return [];
      }
    }

    for (var attempt = 1; attempt <= config.fetchMaxRetries; attempt++) {
      try {
        final resp = await dio.get<String>(
          url,
          options: Options(
            sendTimeout: Duration(seconds: config.fetchConnectTimeout),
            receiveTimeout: Duration(seconds: config.fetchTimeout),
          ),
        );
        final text = resp.data ?? '';
        return parser.parseAdaptive(text);
      } on DioException {
        if (attempt < config.fetchMaxRetries) {
          await Future.delayed(Duration(seconds: config.fetchRetryDelay));
        }
      }
    }
    return [];
  }

  /// 拉取单个 ASN 公告前缀（RIPE Stat）。
  Future<List<String>> fetchAsnPrefixes(int asn, AppConfig config) async {
    final url = 'https://stat.ripe.net/data/announced-prefixes/data.json?resource=AS$asn';
    for (var attempt = 1; attempt <= config.asnSourceRetryMax; attempt++) {
      try {
        final resp = await dio.get<Map<String, dynamic>>(
          url,
          queryParameters: {'starttime': '1970-01-01T00:00'},
          options: Options(
            sendTimeout: Duration(seconds: config.asnSourceConnectTimeout),
            receiveTimeout: Duration(seconds: config.asnSourceTimeout),
          ),
        );
        final data = resp.data ?? {};
        return parser.parseRipePrefixes(data, config.asnSourcesIpv6);
      } on DioException {
        if (attempt < config.asnSourceRetryMax) {
          await Future.delayed(Duration(seconds: config.asnSourceRetryDelay));
        }
      }
    }
    return [];
  }

  /// 加载所有数据源（附加源 + ASN 前缀），去重返回节点列表。
  Future<List<String>> loadAllSources(AppConfig config, {bool skipFetch = false, String? cachedFile}) async {
    final nodes = <String>[];

    if (skipFetch && cachedFile != null && await File(cachedFile).exists()) {
      final lines = await File(cachedFile).readAsLines();
      for (final line in lines) {
        final s = line.trim();
        if (s.isNotEmpty) nodes.add(s);
      }
      return nodes;
    }

    final enabled = config.additionalSources.where((s) => s.enabled && s.url.isNotEmpty).toList();
    final results = await Future.wait(
      enabled.map((s) => fetchAdditionalSource(s.url, config)),
    );
    final seen = <String>{};
    for (final v in results) {
      for (final n in v) {
        final key = n.split('#').first;
        if (seen.add(key)) nodes.add(n);
      }
    }

    if (config.asnSourcesEnabled) {
      final prefixes = <String>[];
      final asnResults = await Future.wait(
        config.asnSources.map((a) => fetchAsnPrefixes(a, config)),
      );
      for (final p in asnResults) prefixes.addAll(p);
      final expanded = parser.expandPrefixesToNodes(
        prefixes,
        config.asnSourceMaxIps,
        config.asnSourcePort,
        config.asnSourceCountry,
      );
      for (final n in expanded) {
        final key = n.split('#').first;
        if (seen.add(key)) nodes.add(n);
      }
    }

    return nodes;
  }
}
