import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import '../../core/error/exceptions.dart';
import '../../core/error/failure.dart';
import '../../domain/entities/source_config.dart';

/// 底层异常 → 领域 [Failure] 的统一收敛器。
///
/// 为什么要独立成类？
/// ------------------------------------------------------------------
/// 聚合搜索会对 N 个源各自发起请求，若不收敛，调用方就要处理
/// `DioException` / `TimeoutException` / `SocketException` / `FormatException`
/// 等 6+ 种异常类型，极易漏判。集中映射后，上层只需 switch [Failure] 子类。
class FailureMapper {
  const FailureMapper._();

  static Failure map(Object error, {SourceConfig? source, String? url}) {
    final target = url ?? source?.api;

    if (error is Failure) return error;

    if (error is TimeoutException) {
      return TimeoutFailure('请求超时', url: target, cause: error);
    }

    if (error is HttpStatusException) {
      return SourceUnavailableFailure(
        '源站返回 HTTP ${error.statusCode}',
        sourceKey: source?.key ?? '',
        statusCode: error.statusCode,
        cause: error,
      );
    }

    if (error is ResponseDecodeException) {
      return ParseFailure(
        '响应不是有效 JSON（可能被 CDN 劫持或需要人机验证）',
        rawSnippet: error.snippet,
        cause: error,
      );
    }

    if (error is SourceParseException) {
      return ParseFailure(error.message, cause: error);
    }

    if (error is ProtocolVersionException) {
      return ParseFailure(
        '订阅协议版本不兼容：收到 ${error.received}，客户端支持 ${error.supported}',
        cause: error,
      );
    }

    if (error is SourceConfigException) {
      return SourceUnavailableFailure(
        error.message,
        sourceKey: source?.key ?? '',
        cause: error,
      );
    }

    if (error is DioException) return _mapDio(error, source, target);

    if (error is SocketException) {
      return NetworkFailure(
        '网络连接失败：${error.osError?.message ?? error.message}',
        cause: error,
        url: target,
      );
    }

    if (error is FormatException) {
      return ParseFailure('数据格式异常：${error.message}', cause: error);
    }

    return UnknownFailure('${error.runtimeType}: $error', cause: error);
  }

  static Failure _mapDio(DioException error, SourceConfig? source, String? url) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return TimeoutFailure('请求超时', url: url, cause: error);

      case DioExceptionType.badResponse:
        final status = error.response?.statusCode ?? -1;
        return SourceUnavailableFailure(
          '源站返回 HTTP $status',
          sourceKey: source?.key ?? '',
          statusCode: status,
          cause: error,
        );

      case DioExceptionType.cancel:
        return UnknownFailure('请求已取消', cause: error);

      case DioExceptionType.badCertificate:
        return NetworkFailure('TLS 证书校验失败', cause: error, url: url);

      case DioExceptionType.connectionError:
        return NetworkFailure('无法连接到源站', cause: error, url: url);

      case DioExceptionType.unknown:
        final inner = error.error;
        if (inner is SocketException) {
          return NetworkFailure(
            '网络不可达：${inner.osError?.message ?? inner.message}',
            cause: error,
            url: url,
          );
        }
        return NetworkFailure('网络错误：${error.message ?? '未知'}',
            cause: error, url: url);
    }
  }
}
