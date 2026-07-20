import 'package:dio/dio.dart' as dio_pkg;
import 'package:flutter_test/flutter_test.dart';

import 'package:cfnb_app/features/subscriptions/subscriptions_state.dart';

dio_pkg.RequestOptions _opts() => dio_pkg.RequestOptions(path: '/x');

void main() {
  group('classifyFetchError', () {
    test('connectionTimeout 分类为连接超时', () {
      final e = dio_pkg.DioException(
        type: dio_pkg.DioExceptionType.connectionTimeout,
        requestOptions: _opts(),
      );
      expect(classifyFetchError(e, 'https://a.com/sub'), contains('连接超时'));
    });

    test('sendTimeout 分类为连接超时', () {
      final e = dio_pkg.DioException(
        type: dio_pkg.DioExceptionType.sendTimeout,
        requestOptions: _opts(),
      );
      expect(classifyFetchError(e, 'https://a.com/sub'), contains('连接超时'));
    });

    test('receiveTimeout 分类为读取超时', () {
      final e = dio_pkg.DioException(
        type: dio_pkg.DioExceptionType.receiveTimeout,
        requestOptions: _opts(),
      );
      expect(classifyFetchError(e, 'https://a.com/sub'), contains('读取超时'));
    });

    test('badResponse 403 含 HTTP 403 与 BEST_SUB 提示', () {
      final e = dio_pkg.DioException(
        type: dio_pkg.DioExceptionType.badResponse,
        response: dio_pkg.Response(
          statusCode: 403,
          requestOptions: _opts(),
        ),
        requestOptions: _opts(),
      );
      final msg = classifyFetchError(e, 'https://a.com/sub');
      expect(msg, contains('HTTP 403'));
      expect(msg, contains('BEST_SUB'));
    });

    test('badResponse 403 但非 /sub 路径不提示 BEST_SUB', () {
      final e = dio_pkg.DioException(
        type: dio_pkg.DioExceptionType.badResponse,
        response: dio_pkg.Response(
          statusCode: 403,
          requestOptions: _opts(),
        ),
        requestOptions: _opts(),
      );
      final msg = classifyFetchError(e, 'https://a.com/api');
      expect(msg, contains('HTTP 403'));
      expect(msg, isNot(contains('BEST_SUB')));
    });

    test('connectionError 分类为连接失败', () {
      final e = dio_pkg.DioException(
        type: dio_pkg.DioExceptionType.connectionError,
        requestOptions: _opts(),
      );
      expect(classifyFetchError(e, 'https://a.com/sub'), contains('连接失败'));
    });

    test('unknown 类型 DioException 分类为请求异常', () {
      final e = dio_pkg.DioException(
        type: dio_pkg.DioExceptionType.unknown,
        error: Exception('boom'),
        requestOptions: _opts(),
      );
      expect(classifyFetchError(e, 'https://a.com/sub'), contains('请求异常'));
    });

    test('非 DioException 分类为未知错误', () {
      expect(classifyFetchError(Exception('boom'), 'https://a.com/sub'),
          contains('未知错误'));
    });
  });
}
