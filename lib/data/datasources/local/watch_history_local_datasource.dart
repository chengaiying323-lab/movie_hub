import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_constants.dart';
import '../../../domain/entities/watch_record.dart';
import '../../adapters/watch_record_adapter.dart';

/// 观影记录本地存储（Hive）。
///
/// 存储选型
/// ------------------------------------------------------------------
/// | 候选 | 结论 |
/// |---|---|
/// | `shared_preferences` | ✗ 只能整块读写字符串列表，"改一条要重写全部"，随记录数增长会明显变慢 |
/// | `sqflite` | ✗ Windows 需额外引入 `sqflite_common_ffi` + `sqlite3_flutter_libs` 并手动初始化 FFI |
/// | `isar` | ✗ v3 需 `build_runner` 代码生成，且对新版 Flutter 兼容性反复 |
/// | **`hive`** | ✓ 纯 Dart、Windows/iOS 开箱可用、Box 按 key 索引，**配手写适配器则完全免代码生成** |
///
/// 数据形态：`Box<WatchRecord>`，键为 `WatchRecord.id`（`{sourceKey}:{vodId}`）。
/// 以键索引意味着单条更新是 O(1) 的 `put`，不需要读-改-写整个列表。
///
/// 离线能力：`WatchRecord` 冗余存储了标题与海报 URL，
/// 因此即使所有数据源都不可达，资料库仍能完整渲染。
class WatchHistoryLocalDataSource {
  WatchHistoryLocalDataSource({Box<WatchRecord>? box}) : _injected = box;

  /// 注入已打开的 Box（单元测试用 `Hive.openBox(name, bytes: ...)` 传入）。
  final Box<WatchRecord>? _injected;

  Box<WatchRecord>? _cached;
  static bool _initialized = false;

  /// 应用启动时调用一次：初始化 Hive 目录并注册适配器。
  ///
  /// 必须在 [Hive.openBox] 之前完成——Box 会用 `typeId` 反查适配器，
  /// 未注册时打开含自定义对象的 Box 会抛 `HiveError`。
  static Future<void> initialize() async {
    if (_initialized) return;
    // 桌面端落到「应用文档目录」，iOS 落到沙盒 Documents；
    // 两者都在应用私有空间内，无需额外权限声明。
    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(kWatchRecordTypeId)) {
      // 不带 `const`：`TypeAdapter`（hive 2.2.3）没有声明构造器，
      // 其隐式默认构造器是非 const 的，`WatchRecordAdapter` 因此也
      // 不能是 const 构造器。详见该类的文档注释。
      Hive.registerAdapter(WatchRecordAdapter());
    }
    _initialized = true;
  }

  /// 懒开 Box。多次调用只会返回同一个实例。
  Future<Box<WatchRecord>> get box async {
    final injected = _injected;
    if (injected != null) return injected;

    final cached = _cached;
    if (cached != null && cached.isOpen) return cached;

    await initialize();
    final opened = Hive.isBoxOpen(AppConstants.kWatchRecordBox)
        ? Hive.box<WatchRecord>(AppConstants.kWatchRecordBox)
        : await Hive.openBox<WatchRecord>(AppConstants.kWatchRecordBox);
    _cached = opened;
    return opened;
  }

  // ── 读 ──────────────────────────────────────────────────

  /// 全量读取，按 `updatedAt` 倒序。
  ///
  /// 只提供全量读：记录数上限 500，且资料库三分栏 / 续播判定都需要全量视图，
  /// 因此在内存建索引比按键回表更简单也更快
  /// （理由同 `WatchHistoryRepository` 的接口注释）。
  Future<List<WatchRecord>> readAll() async {
    final target = await box;
    final list = target.values.toList(growable: false);
    return list.toList()..sort(WatchRecord.byUpdatedAtDesc);
  }

  // ── 写 ──────────────────────────────────────────────────

  Future<void> write(WatchRecord record) async {
    final target = await box;
    await target.put(record.id, record);
  }

  Future<void> delete(String id) async {
    final target = await box;
    await target.delete(id);
  }

  /// 删除某一状态的全部记录，返回删除条数。
  Future<int> deleteByStatus(WatchStatus status) async {
    final target = await box;
    final doomed = <dynamic>[
      for (final key in target.keys)
        if (target.get(key)?.status == status) key,
    ];
    if (doomed.isEmpty) return 0;
    await target.deleteAll(doomed);
    return doomed.length;
  }

  Future<void> clear() async => (await box).clear();

  /// 超出上限时淘汰记录，返回淘汰条数。
  ///
  /// 淘汰优先级（先删权重低的）：
  /// `已看` → `想看` → `正在看`。
  /// 同一优先级内按 `updatedAt` 升序，即**最旧的先删**。
  Future<int> enforceLimit({
    int max = AppConstants.kMaxWatchRecords,
  }) async {
    final target = await box;
    if (target.length <= max) return 0;

    final sorted = target.values.toList()..sort(WatchRecord.byUpdatedAtDesc);
    final overflow = sorted.sublist(max)
      ..sort((a, b) {
        final byStatus = _evictionWeight(a.status).compareTo(
          _evictionWeight(b.status),
        );
        if (byStatus != 0) return byStatus;
        return a.updatedAt.compareTo(b.updatedAt);
      });

    final doomed = overflow.map((r) => r.id).toList(growable: false);
    await target.deleteAll(doomed);
    return doomed.length;
  }

  static int _evictionWeight(WatchStatus status) {
    switch (status) {
      case WatchStatus.watched:
        return 0;
      case WatchStatus.wantToWatch:
        return 1;
      case WatchStatus.watching:
        return 2;
    }
  }

  // ── 旧数据迁移 ──────────────────────────────────────────

  /// 把第二阶段遗留在 SharedPreferences 中的
  /// `watch_progress.v1` / `favorites.v1` 迁移进 Hive。
  ///
  /// 幂等：以 [AppConstants.kWatchMigrationDoneKey] 标记，
  /// 且**绝不覆盖**新库中已存在的键；单条脏数据解析失败会被跳过而非中断整体。
  ///
  /// 返回迁移条数（0 表示无需迁移或已迁移过）。
  Future<int> migrateLegacyIfNeeded({SharedPreferences? preferences}) async {
    final prefs = preferences ?? await SharedPreferences.getInstance();
    if (prefs.getBool(AppConstants.kWatchMigrationDoneKey) == true) return 0;

    final migrated = <String, WatchRecord>{};

    // 1) 旧的「观看进度」→ watching / watched（按进度阈值判定）
    for (final raw in prefs.getStringList(AppConstants.kLegacyProgressKey) ??
        const <String>[]) {
      final record = _decodeLegacy(raw, fromFavorite: false);
      if (record != null) migrated[record.id] = record;
    }

    // 2) 旧的「追剧收藏」→ wantToWatch（不覆盖上一步已有的进度记录）
    for (final raw in prefs.getStringList(AppConstants.kLegacyFavoritesKey) ??
        const <String>[]) {
      final record = _decodeLegacy(raw, fromFavorite: true);
      if (record != null) migrated.putIfAbsent(record.id, () => record);
    }

    if (migrated.isNotEmpty) {
      final target = await box;
      final fresh = <String, WatchRecord>{
        for (final entry in migrated.entries)
          if (!target.containsKey(entry.key)) entry.key: entry.value,
      };
      if (fresh.isNotEmpty) await target.putAll(fresh);
    }

    await prefs.setBool(AppConstants.kWatchMigrationDoneKey, true);
    // 迁移成功后清掉旧键，避免同一份数据长期占用两份存储
    await prefs.remove(AppConstants.kLegacyProgressKey);
    await prefs.remove(AppConstants.kLegacyFavoritesKey);
    return migrated.length;
  }

  /// 解析单条旧数据。
  ///
  /// 复用了 [WatchRecord.fromMap] 的字段兼容能力（`poster` / `episode_name` /
  /// `position` / `duration` 等旧键名），因此这里只需补齐状态与时间字段。
  WatchRecord? _decodeLegacy(String raw, {required bool fromFavorite}) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);

      final movieId = '${map['movie_id'] ?? ''}';
      if (movieId.isEmpty) return null;

      if (fromFavorite) {
        // 收藏条目从未播放过：进度归零，状态落到「想看」
        final stamp = map['added_at'] ?? DateTime.now().toIso8601String();
        map['updated_at'] ??= stamp;
        map['created_at'] ??= stamp;
        map['status'] ??= WatchStatus.wantToWatch.storageKey;
      } else {
        final percent = _percentOf(map);
        map['status'] ??= (percent >= AppConstants.kWatchedThreshold
                ? WatchStatus.watched
                : WatchStatus.watching)
            .storageKey;
        map['created_at'] ??= map['updated_at'];
      }

      return WatchRecord.fromMap(map);
    } catch (_) {
      // 单条脏数据（截断的 JSON、字段类型异常）不应中断整体迁移
      return null;
    }
  }

  static double _percentOf(Map<String, dynamic> map) {
    final position = _num(map['position_ms']);
    final duration = _num(map['duration_ms']);
    if (duration <= 0) return 0;
    return (position / duration).clamp(0.0, 1.0);
  }

  static double _num(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }
}
