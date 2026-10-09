import '../../domain/entities/source_config.dart';

/// 数据源仓储接口（domain 层声明，data 层实现）。
///
/// 仅负责**持久化**与**订阅包获取**，不包含校验、合并等业务策略
/// —— 那些属于 [SourceManager] 的职责。保持仓储"薄"，便于测试与替换存储实现。
abstract class SourceRepository {
  /// 读取全部本地数据源。
  Future<List<SourceConfig>> loadSources();

  /// 全量覆盖写入。
  Future<void> saveSources(List<SourceConfig> sources);

  /// 增量写入（按 [SourceConfig.key] 覆盖或追加）。
  ///
  /// 返回 `(added, updated)` 数量。
  Future<(int added, int updated)> upsertSources(List<SourceConfig> sources);

  /// 删除指定数据源。
  Future<void> removeSource(String key);

  /// 读取已导入的订阅元信息。
  Future<List<SourceSubscription>> loadSubscriptions();

  /// 保存订阅元信息。
  Future<void> saveSubscriptions(List<SourceSubscription> subscriptions);

  /// 从远程拉取订阅包并解析。
  ///
  /// [etag] 用于条件请求（命中 304 时返回 [SourceSubscription.version] 不变的包，
  /// 或抛出 [NotModifiedException] 由调用方短路）。
  Future<SourceSubscription> fetchSubscription(String url, {String? etag});

  /// 解析订阅包文本（本地文件导入 / 剪贴板粘贴场景）。
  SourceSubscription parseSubscription(String rawJson, {String url});

  /// 清空全部数据源（用于"恢复默认"）。
  Future<void> clear();
}

/// 订阅未被修改（HTTP 304）时抛出的短路信号。
class NotModifiedException implements Exception {
  const NotModifiedException(this.url);
  final String url;

  @override
  String toString() => 'NotModifiedException($url)';
}
