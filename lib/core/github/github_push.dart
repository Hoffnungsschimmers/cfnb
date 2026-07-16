import 'dart:convert';

import 'package:dio/dio.dart';

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

  GithubPush({
    required this.token,
    required this.repo,
    this.branch = 'main',
    Dio? dio,
    this.sender,
  }) : dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'https://api.github.com',
              headers: {
                'Authorization': 'Bearer $token',
                'Accept': 'application/vnd.github+json',
              },
            ));

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
    final url = '/repos/$repo/contents/$path';
    String? sha;
    try {
      final existing = await _send(RequestOptions(
        method: 'GET',
        path: url,
        baseUrl: dio.options.baseUrl,
      ));
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
    final resp = await _send(RequestOptions(
      method: 'PUT',
      path: url,
      baseUrl: dio.options.baseUrl,
      data: body,
    ));
    return resp.statusCode ?? 0;
  }
}
