import '../entities/source_config.dart';
import '../entities/source_validation.dart';

/// 数据源管理用例契约（domain 层声明）。
///
/// 实现位于 `data/services/source_manager.dart` 的 `SourceManager`。
/// presentation 层依赖本抽象而非具体实现，便于替换与测试。
///
/// 注意：实现类允许追加可选命名参数（如 `MergePolicy`），
/// 这是 Dart 覆盖规则所允许的，不会破坏契约。
abstract class ManageSourcesUseCase {
  /// 读取全部数据源（按优先级升序）。
  Future<List<SourceConfig>> loadSources({bool enabledOnly = false});

  /// 从订阅地址导入。
  Future<SourceImportReport> importFromUrl(String url);

  /// 从原始 JSON 文本导入。
  Future<SourceImportReport> importFromRaw(String rawJson, {String url = ''});

  /// 校验单个数据源的可用性。
  Future<SourceValidationResult> validate(SourceConfig config);

  /// 批量校验（受控并发）。
  Future<Map<String, SourceValidationResult>> validateAll(
    List<SourceConfig> sources, {
    int concurrency = 5,
  });

  /// 启用 / 禁用指定源。
  Future<void> setEnabled(String key, bool enabled);

  /// 调整优先级（数值越小越优先）。
  Future<void> setPriority(String key, int priority);

  /// 删除指定源。
  Future<void> remove(String key);

  /// 已导入的订阅列表。
  Future<List<SourceSubscription>> loadSubscriptions();

  /// 检查订阅更新，返回 `{订阅ID: (旧版本, 新版本)}`。
  Future<Map<String, (int oldVersion, int newVersion)>> checkUpdates();

  /// 刷新指定订阅。
  Future<SourceImportReport> refreshSubscription(String subscriptionId);
}
