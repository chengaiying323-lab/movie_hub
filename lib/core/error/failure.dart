/// 领域层统一错误模型。
///
/// 设计要点：
/// 1. 使用 `sealed` 密封类，调用方可通过 switch 穷尽分支，编译期防遗漏；
/// 2. UI 层只依赖 [Failure]，不感知 Dio / json 解析等底层实现细节；
/// 3. 所有聚合类操作（多源并发搜索）必须做到"单源失败不影响整体"，
///    因此需要"可定位到源"的失败子类（[SourceUnavailableFailure] /
///    [UnsupportedSourceFailure]）携带 sourceKey。
library;

sealed class Failure implements Exception {
  const Failure(this.message, {this.cause, this.stackTrace});

  /// 面向用户的可读描述。
  final String message;

  /// 原始异常对象，便于日志与埋点上报。
  final Object? cause;

  final StackTrace? stackTrace;

  @override
  String toString() => '$runtimeType(message: $message, cause: $cause)';
}

/// 网络层错误：连接失败、DNS 失败、非 2xx 状态码等。
final class NetworkFailure extends Failure {
  const NetworkFailure(
    super.message, {
    this.statusCode,
    this.url,
    super.cause,
    super.stackTrace,
  });

  final int? statusCode;
  final String? url;
}

/// 超时错误：与 [NetworkFailure] 分离，便于 UI 提供"重试/换源"差异化引导。
///
/// ⚠️ 构造参数刻意与其它子类保持一致：`message` 是**必填位置参数**，
/// `url` / `cause` / `stackTrace` 走命名参数。
///
/// 原先写成了 `TimeoutFailure([super.message = '请求超时'], {this.url, ...})`
/// —— 这在 Dart 里是**非法签名**：
/// 「可选参数要么全用命名、要么全用位置，不能混用」
/// （ECMA-408 §9.2 / dart.dev：*optional parameters can be specified either as
/// a set of named parameters or as a list of positional parameters, but not both*）。
/// 解析器会丢掉 `{...}` 那一半，于是编译器接着报两串误导性错误：
/// `Final field 'url' is not initialized` 和调用点的
/// `No named parameter with the name 'url' / 'cause'`。
final class TimeoutFailure extends Failure {
  const TimeoutFailure(
    super.message, {
    this.url,
    super.cause,
    super.stackTrace,
  });

  final String? url;
}

/// 解析错误：响应非 JSON、字段缺失、播放串格式非法等。
final class ParseFailure extends Failure {
  const ParseFailure(
    super.message, {
    this.rawSnippet,
    super.cause,
    super.stackTrace,
  });

  /// 原始响应片段（截断），用于定位源站改版问题。
  final String? rawSnippet;
}

/// 数据源不可用 / 配置非法。
final class SourceUnavailableFailure extends Failure {
  const SourceUnavailableFailure(
    super.message, {
    required this.sourceKey,
    this.statusCode,
    super.cause,
    super.stackTrace,
  });

  final String sourceKey;
  final int? statusCode;
}

/// 数据源协议不受客户端支持（例如 TVBox spider 类型的 JS/Java 源）。
final class UnsupportedSourceFailure extends Failure {
  const UnsupportedSourceFailure(
    super.message, {
    required this.sourceKey,
    required this.kind,
    super.cause,
    super.stackTrace,
  });

  final String sourceKey;
  final String kind;
}

/// 本地缓存读写错误。
final class CacheFailure extends Failure {
  const CacheFailure(super.message, {super.cause, super.stackTrace});
}

/// 兜底错误。
///
/// 同样去掉了原先 `([super.message = '未知错误'], {...})` 的非法签名
/// （原因见 [TimeoutFailure]）。`message` 现在是必填位置参数，
/// 与其它子类一致；唯一的构造方是 `data/mappers/failure_mapper.dart` 里的
/// `FailureMapper`，它总会带上 `runtimeType + 原始异常` 的描述，
/// 所以原来那个"默认文案"实际用不上。
final class UnknownFailure extends Failure {
  const UnknownFailure(super.message, {super.cause, super.stackTrace});
}
