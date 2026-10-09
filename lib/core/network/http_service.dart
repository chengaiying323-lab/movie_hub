import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../constants/app_constants.dart';
import '../error/exceptions.dart';

/// 统一的 HTTP 出口。
///
/// 关键设计决策：
/// 1. **以 bytes 接收响应体**：影视源站大量使用 GBK/GB2312 编码，Dio 默认按
///    UTF-8 解码会产生乱码。这里先拿字节流再按 `Content-Type` 声明解码。
/// 2. **`validateStatus` 恒为 true**：状态码由业务层判断，避免 Dio 把 4xx/5xx
///    包装成 DioException 后丢失响应体（很多 CMS 用 4xx 返回真实业务 JSON）。
/// 3. **URL 去重缓存**：同一轮聚合搜索中重复 URL 直接命中缓存，降低对源站压力。
class HttpService {
  HttpService({
    Dio? dio,
    Map<String, String>? defaultHeaders,
    Duration? connectTimeout,
    Duration? receiveTimeout,
  })  : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: connectTimeout ?? AppConstants.connectTimeout,
                receiveTimeout: receiveTimeout ?? AppConstants.receiveTimeout,
                sendTimeout: AppConstants.connectTimeout,
                followRedirects: true,
                maxRedirects: 5,
                headers: defaultHeaders ?? AppConstants.defaultHeaders,
              ),
            ),
        _ownsClient = dio == null;

  final Dio _dio;
  final bool _ownsClient;

  /// 短周期内存缓存：key = 完整 URL，value = 已解析的 JSON。
  /// 仅用于单次聚合搜索窗口内的去重，不做长期缓存（源站数据时效性要求高）。
  final Map<String, Object?> _memo = <String, Object?>{};

  void clearMemo() => _memo.clear();

  void dispose() {
    if (_ownsClient) _dio.close(force: true);
  }

  /// 发起 GET 并解析为 JSON（Map 或 List）。
  ///
  /// [headers] 会与默认头合并，源站级配置可覆盖 UA / Referer。
  Future<Object?> getJson(
    String url, {
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    Duration? timeout,
    bool useMemo = false,
  }) async {
    final requestUrl = _buildUrl(url, query);
    if (useMemo && _memo.containsKey(requestUrl)) {
      return _memo[requestUrl];
    }

    final stopwatch = Stopwatch()..start();
    try {
      final response = await _dio.get<List<int>>(
        url,
        queryParameters: query,
        options: Options(
          responseType: ResponseType.bytes,
          headers: headers == null ? null : <String, dynamic>{...headers},
          receiveTimeout: timeout ?? AppConstants.receiveTimeout,
          validateStatus: (_) => true,
        ),
      );

      final statusCode = response.statusCode ?? 0;
      final bodyBytes = response.data ?? const <int>[];
      final contentType = response.headers.value(Headers.contentTypeHeader);
      final text = decodeBody(bodyBytes, contentType);

      if (statusCode < 200 || statusCode >= 400) {
        throw HttpStatusException(
          statusCode,
          requestUrl,
          bodySnippet: _snippet(text),
        );
      }

      final trimmed = text.trimLeft();
      if (trimmed.isEmpty) {
        throw ResponseDecodeException(requestUrl, '<empty body>');
      }
      // 被 CDN 劫持 / 需要 JS 跳转的典型特征
      if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) {
        throw ResponseDecodeException(requestUrl, _snippet(text));
      }

      final Object? json = jsonDecode(text);
      if (useMemo) _memo[requestUrl] = json;
      return json;
    } on DioException catch (error) {
      throw _mapDioException(error, requestUrl, stopwatch.elapsedMilliseconds);
    }
  }

  /// 原始文本获取（用于拉取 m3u8 播放列表、订阅文本等非 JSON 资源）。
  Future<String> getText(
    String url, {
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    final requestUrl = _buildUrl(url, query);
    try {
      final response = await _dio.get<List<int>>(
        url,
        queryParameters: query,
        options: Options(
          responseType: ResponseType.bytes,
          headers: headers == null ? null : <String, dynamic>{...headers},
          receiveTimeout: timeout ?? AppConstants.receiveTimeout,
          validateStatus: (_) => true,
        ),
      );
      final statusCode = response.statusCode ?? 0;
      final text = decodeBody(
        response.data ?? const <int>[],
        response.headers.value(Headers.contentTypeHeader),
      );
      if (statusCode < 200 || statusCode >= 400) {
        throw HttpStatusException(statusCode, requestUrl,
            bodySnippet: _snippet(text));
      }
      return text;
    } on DioException catch (error) {
      throw _mapDioException(error, requestUrl, 0);
    }
  }

  /// 轻量连通性探测：只判断"能否在超时内拿到 2xx 响应"，不解析内容。
  /// 返回 HTTP 状态码；网络不可达统一返回 `-1`。
  Future<int> ping(
    String url, {
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    try {
      final response = await _dio.head<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: headers == null ? null : <String, dynamic>{...headers},
          receiveTimeout: timeout ?? const Duration(seconds: 5),
          validateStatus: (_) => true,
        ),
      );
      return response.statusCode ?? -1;
    } catch (_) {
      return -1;
    }
  }

  // ── 内部工具 ────────────────────────────────────────────

  String _buildUrl(String url, Map<String, dynamic>? query) {
    if (query == null || query.isEmpty) return url;
    final pairs = query.entries.map((e) => '${e.key}=${e.value}').join('&');
    return '$url${url.contains('?') ? '&' : '?'}$pairs';
  }

  /// 响应体解码。
  ///
  /// 已知限制：Dart 标准库不内置 GBK 解码器。
  /// 若目标源站返回 GBK，可引入 `fast_gbk` 并在下方分支替换实现：
  /// ```dart
  /// if (_isGbk(charset)) return FastGbk.decode(bytes);
  /// ```
  /// 当前实现优先保证可编译与 UTF-8 源站（主流苹果CMS 均已是 UTF-8）。
  static String decodeBody(List<int> bytes, String? contentType) {
    final charset = _extractCharset(contentType);
    if (charset != null &&
        (charset.contains('gbk') || charset.contains('gb2312'))) {
      // GBK 源站：此处接入 fast_gbk 的 `FastGbk.decode(bytes)` 即可。
      // 当前以 UTF-8 + 容错模式解码，保证不抛异常、不阻塞主流程。
      return utf8.decode(bytes, allowMalformed: true);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  static String? _extractCharset(String? contentType) {
    if (contentType == null) return null;
    final match = RegExp(r'charset=([\w-]+)', caseSensitive: false)
        .firstMatch(contentType);
    return match?.group(1)?.toLowerCase();
  }

  static String _snippet(String text) =>
      text.length <= 160 ? text : '${text.substring(0, 160)}...';

  DioException _mapDioException(
    DioException error,
    String url,
    int elapsedMs,
  ) {
    final type = error.type;
    if (type == DioExceptionType.connectionTimeout ||
        type == DioExceptionType.receiveTimeout ||
        type == DioExceptionType.sendTimeout) {
      return DioException(
        requestOptions: error.requestOptions,
        type: type,
        error: TimeoutException('请求 $url 超时（${elapsedMs}ms）'),
        message: '请求超时',
      );
    }
    return error;
  }
}
