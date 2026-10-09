import '../entities/watch_record.dart';

/// 观影记录仓储（domain 层声明，data 层以 Hive 实现）。
///
/// 与「数据源仓储」分离的原因：数据源是**可订阅、可热更新的公共配置**，
/// 而观影记录是**用户私有数据**——两者的生命周期、备份策略与隐私等级完全不同。
///
/// 约定：记录以 [WatchRecord.id]（即 `{sourceKey}:{vodId}`）为唯一键，
/// 因此本接口中 `id` 与 `movieId` 是同一个值。
///
/// 为什么只有「全量读」而没有 `findById` / `count`？
/// 记录数硬上限为 500 条（见 `AppConstants.kMaxWatchRecords`），
/// 资料库三分栏、首页「继续观看」、详情页续播判定**都需要全量视图**；
/// 一次 [loadAll] 后在内存建立索引，比每次按键回表既更简单也更快，
/// 因此**不提供**按 id 的零散读取接口——那是用不上的 API 面积。
abstract class WatchHistoryRepository {
  /// 读取全量记录，按 `updatedAt` 倒序（保证首条即最近观看）。
  Future<List<WatchRecord>> loadAll();

  /// 新增或覆盖单条（`updatedAt` 由调用方决定，仓储不擅自改写时间）。
  ///
  /// 实现方需在写入后做一次容量治理，确保记录数不超过上限。
  Future<void> upsert(WatchRecord record);

  /// 删除单条。
  Future<void> remove(String id);

  /// 仅删除某一状态的记录，返回删除条数。
  Future<int> removeByStatus(WatchStatus status);

  /// 清空全部记录。
  Future<void> clear();
}
