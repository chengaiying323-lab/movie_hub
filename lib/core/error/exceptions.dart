/// 数据层内部异常。
///
/// 这些异常**不允许**逃逸到 domain / presentation 层，
/// 必须在 repository 实现层通过 [Failure] 收敛。
library;

/// HTTP 层异常。
class HttpStatusException implements Exception {
  const HttpStatusException(this.statusCode, this.url, {this.bodySnippet});

  final int statusCode;
  final String url;
  final String? bodySnippet;

  @override
  String toString() => 'HttpStatusException($statusCode) @ $url';
}

/// 响应体解码失败（非 JSON / 编码错误 / 被 CDN 劫持为 HTML）。
class ResponseDecodeException implements Exception {
  const ResponseDecodeException(this.url, this.snippet);

  final String url;
  final String snippet;

  @override
  String toString() => 'ResponseDecodeException @ $url -> $snippet';
}

/// 数据源解析失败。
class SourceParseException implements Exception {
  const SourceParseException(this.message, {this.sourceKey, this.cause});

  final String message;
  final String? sourceKey;
  final Object? cause;

  @override
  String toString() => 'SourceParseException($sourceKey): $message';
}

/// 数据源配置非法（订阅包字段缺失、api 非法等）。
class SourceConfigException implements Exception {
  const SourceConfigException(this.message, {this.subscriptionId});

  final String message;
  final String? subscriptionId;

  @override
  String toString() => 'SourceConfigException($subscriptionId): $message';
}

/// 订阅协议版本不兼容。
class ProtocolVersionException implements Exception {
  const ProtocolVersionException(this.received, this.supported);

  final String received;
  final String supported;

  @override
  String toString() =>
      'ProtocolVersionException: 订阅协议 $received 高于客户端支持的 $supported';
}
