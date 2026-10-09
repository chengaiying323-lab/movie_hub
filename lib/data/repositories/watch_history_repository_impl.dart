import '../../domain/entities/watch_record.dart';
import '../../domain/repositories/watch_history_repository.dart';
import '../datasources/local/watch_history_local_datasource.dart';

/// 观影记录仓储的 Hive 实现。
///
/// 职责边界：只做「领域对象 ↔ 存储」的搬运与容量治理，
/// **不做任何状态机判断**（何时该变成「已看」属于
/// `WatchHistoryNotifier` 的策略）。
/// 保持仓储"薄"，是为了让状态机可以脱离存储单独测试。
class WatchHistoryRepositoryImpl implements WatchHistoryRepository {
  WatchHistoryRepositoryImpl({required WatchHistoryLocalDataSource local})
      : _local = local;

  final WatchHistoryLocalDataSource _local;

  @override
  Future<List<WatchRecord>> loadAll() => _local.readAll();

  @override
  Future<void> upsert(WatchRecord record) async {
    await _local.write(record);
    // 每次写入后做一次轻量容量检查：Box.length 是 O(1)，超限才会真正淘汰
    await _local.enforceLimit();
  }

  @override
  Future<void> remove(String id) => _local.delete(id);

  @override
  Future<int> removeByStatus(WatchStatus status) =>
      _local.deleteByStatus(status);

  @override
  Future<void> clear() => _local.clear();
}
