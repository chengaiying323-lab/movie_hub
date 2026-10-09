import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/error/exceptions.dart';
import '../../../core/network/http_service.dart';
import '../../../domain/entities/source_config.dart';
import '../../../domain/repositories/source_repository.dart';
import '../local/source_local_datasource.dart';

/// 远程订阅获取实现。
///
/// 支持的订阅格式（自动嗅探，无需用户指定）：
/// 1. **本协议**：`{ "protocol": "moviehub/v1", "version": 3, "sources": [...] }`
/// 2. **TVBox 生态**：`{ "sites": [...], "parses": [...], "lives": [...] }`
///    —— 仅提取 `sites`，`parses`/`lives` 属于协议外能力，忽略并记录。
/// 3. **裸数组**：`[ {...}, {...} ]`（部分站点聚合页直出）
class SourceRemoteDataSource implements RemoteSubscriptionFetcher {
  SourceRemoteDataSource({required HttpService http}) : _http = http;

  final HttpService _http;

  @override
  Future<SourceSubscription> fetch(String url, {String? etag}) async {
    final headers = <String, String>{...AppConstants.defaultHeaders};
    if (etag != null && etag.trim().isNotEmpty) {
      headers['If-None-Match'] = etag;
    }

    final Object? payload;
    try {
      payload = await _http.getJson(
        url,
        headers: headers,
        timeout: const Duration(seconds: 15),
      );
    } on HttpStatusException catch (error) {
      // 304 Not Modified：订阅未变更，由上层短路处理。
      if (error.statusCode == 304) {
        throw NotModifiedException(url);
      }
      rethrow;
    } on DioException catch (error) {
      if (error.response?.statusCode == 304) {
        throw NotModifiedException(url);
      }
      rethrow;
    }

    final subscription = _convert(payload, url: url);

    // 补上 ETag，供下次条件请求使用。
    return subscription.copyWith(etag: _extractEtag(payload));
  }

  @override
  SourceSubscription parse(String rawJson, {String url = ''}) {
    final Object? decoded;
    try {
      decoded = jsonDecode(rawJson);
    } on FormatException catch (error) {
      throw SourceConfigException('订阅内容不是合法 JSON：${error.message}');
    }
    return _convert(decoded, url: url);
  }

  // ── 内部 ────────────────────────────────────────────────

  SourceSubscription _convert(Object? payload, {required String url}) {
    if (payload == null) {
      throw const SourceConfigException('订阅内容为空');
    }

    // 形态 3：裸数组
    if (payload is List) {
      final sources = payload
          .whereType<Map>()
          .map((e) => SourceConfig.fromJson(e.cast<String, dynamic>()))
          .toList(growable: false);
      if (sources.isEmpty) {
        throw const SourceConfigException('订阅数组中没有可用的数据源定义');
      }
      return SourceSubscription(
        id: 'sub_${DateTime.now().millisecondsSinceEpoch}',
        name: _deriveNameFromUrl(url),
        url: url,
        version: 1,
        sources: sources,
        protocol: AppConstants.protocolVersion,
      );
    }

    if (payload is! Map) {
      throw const SourceConfigException('订阅内容结构无法识别（应为对象或数组）');
    }

    final map = payload.cast<String, dynamic>();
    final subscription = SourceSubscription.fromJson(map, url: url);

    if (subscription.sources.isEmpty) {
      throw const SourceConfigException(
        '订阅中未解析出任何数据源（请确认包含 sources 或 sites 字段）',
      );
    }
    return subscription;
  }

  static String? _extractEtag(Object? payload) {
    if (payload is Map) {
      final etag = payload['etag'];
      if (etag is String && etag.trim().isNotEmpty) return etag.trim();
    }
    return null;
  }

  static String _deriveNameFromUrl(String url) {
    if (url.trim().isEmpty) return '本地导入订阅';
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) return segments.last;
      return uri.host;
    } catch (_) {
      return '订阅';
    }
  }
}
