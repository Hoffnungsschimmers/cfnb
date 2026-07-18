import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/src/adapters/io_adapter.dart';

/// GitHub 文件推送（对应旧版 scripts/git_sync.ps1 的 ip 数据推送）。
///
/// 推送到独立的 cf-ip 仓库（与代码仓库隔离）。使用 GitHub Contents API，
/// 自动处理已存在文件的 sha（更新）或新建。token 通过参数传入，不落盘明文。
class GithubPush {
  final String token;
  final String repo; // 形如 "owner/cf-ip"
  final String branch;
  final Dio dio;

  /// 可选：自定义请求发送器，便于测试注入假网络层。
  final Future<Response> Function(RequestOptions)? sender;

  /// 共享直连 Dio：不覆盖 findProxy，因此走系统代理（Flutter 默认），
  /// 适用于订阅抓取等需经本地代理可达源的请求。
  static Dio directDio() => Dio(BaseOptions(
        headers: {'User-Agent': 'cfnb-app'},
        connectTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 20),
      ));

  /// 仅允许推送优选结果文件（文件名以 _top.txt 结尾，如 addressesapi_top.txt），其余文件不推送。
  static bool isPushable(String file) =>
      file.toLowerCase().endsWith('_top.txt');

  GithubPush({
    required this.token,
    required this.repo,
    this.branch = 'main',
    Dio? dio,
    this.sender,
  }) : dio = dio ??
        Dio(BaseOptions(
          baseUrl: 'https://api.github.com',
          validateStatus: (_) => true,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
          headers: {
            'Authorization': 'Bearer ${token.trim()}',
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'cfnb-app',
          },
        )) {
    // GitHub API 走直连，绕开本地代理（如 127.0.0.1:7890 的 Clash）——
    // 经代理访问 api.github.com 会被阻断/丢弃（实测 HTTP 000），直连则正常。
    final adapter = this.dio.httpClientAdapter;
    if (adapter is IOHttpClientAdapter) {
      adapter.createHttpClient = () {
        final client = HttpClient();
        client.findProxy = (uri) => 'DIRECT';
        client.userAgent = 'cfnb-app';
        return client;
      };
    }
  }

  /// 构造单次请求：把 Token / UA 显式带到 RequestOptions，避免某些 Dio 版本
  /// 在 `fetch()` 时不继承 BaseOptions.headers 导致 401。
  RequestOptions _req(String method, String path, {Map<String, dynamic>? data}) {
    final headers = <String, dynamic>{
      'Authorization': 'Bearer ${token.trim()}',
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'cfnb-app',
    };
    return RequestOptions(
      method: method,
      path: path,
      baseUrl: dio.options.baseUrl,
      headers: headers,
      data: data,
      validateStatus: dio.options.validateStatus,
      connectTimeout: dio.options.connectTimeout,
      receiveTimeout: dio.options.receiveTimeout,
    );
  }

  Future<Response> _send(RequestOptions options) => sender != null
      ? sender!(options)
      : dio.fetch(options);

  /// 构造 PUT body（提取已有 sha 用于更新，或仅新建）。
  static Map<String, dynamic> buildPutBody({
    required String path,
    required String content,
    required String branch,
    String? message,
    String? sha,
  }) =>
      {
        'message': message ?? 'update $path',
        'content': base64Encode(utf8.encode(content)),
        'branch': branch,
        if (sha != null) 'sha': sha,
      };

  /// 推送单个文件内容到仓库，返回 HTTP 状态码。
  Future<int> pushFile(String path, String content, {String? message}) async {
    // Token 有效性自检：401 立即给出明确提示，避免看 GitHub 原始报错。
    try {
      final who = await _send(_req('GET', '/user'));
      if (who.statusCode == 401) {
        throw Exception(
            'GitHub Token 无效（GitHub 返回 401）。请：① 在 GitHub 网页重新生成 Classic token 并只勾 repo；② 复制时先清空再整段粘贴 \$token，避免带入空格/换行/全角空格');
      }
    } on DioException {
      // /user 异常也按无效处理，由下方 PUT 给出最终错误
    }

    final url = '/repos/$repo/contents/$path';
    String? sha;
    try {
      final existing = await _send(_req('GET', url));
      sha = (existing.data is Map ? existing.data['sha'] as String? : null);
    } on DioException {
      // 文件不存在，新建
    }

    final body = buildPutBody(
      path: path,
      content: content,
      branch: branch,
      message: message,
      sha: sha,
    );
    final resp = await _send(_req('PUT', url, data: body));
    if (resp.statusCode == 401) {
      throw Exception(
          'GitHub 401：Token 无效或无该仓库访问权。请检查：① Token 是否完整无空格/换行；② Repo 是否拼写为「owner/仓名」且 Token 有 repo 权限；③ 该仓确实存在');
    }
    return resp.statusCode ?? 0;
  }

  /// 批量推送多个文件，返回 路径 -> HTTP 状态码 的映射。
  Future<Map<String, int>> pushMultiple(Map<String, String> files, {String? message}) async {
    final results = <String, int>{};
    for (final entry in files.entries) {
      results[entry.key] = await pushFile(entry.key, entry.value, message: message);
    }
    return results;
  }
}
