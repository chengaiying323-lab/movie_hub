import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_constants.dart';
import '../../../domain/entities/source_config.dart';
import '../../../domain/repositories/source_repository.dart';

/// 数据源本地持久化。
///
/// 存储选型：SharedPreferences。
/// 理由：数据源配置总量小（典型 20~200 条，序列化后 < 200KB），
/// 且需要"同步可读、进程启动即可用"；无需引入 sqlite/hive 的复杂度。
/// 若后续源数量上千，可平滑替换为 sqflite —— 上层只依赖仓储接口。
class SourceLocalDataSource {
  SourceLocalDataSource({SharedPreferences? preferences}) : _injected = preferences;

  final SharedPreferences? _injected;
  SharedPreferences? _cached;

  Future<SharedPreferences> get _prefs async =>
      _cached ??= _injected ?? await SharedPreferences.getInstance();

  // ── 数据源 ──────────────────────────────────────────────

  Future<List<SourceConfig>> readSources() async {
    final prefs = await _prefs;
    final raw = prefs.getStringList(AppConstants.kSourcesKey);
    if (raw == null || raw.isEmpty) return <SourceConfig>[];

    final sources = <SourceConfig>[];
    for (final item in raw) {
      try {
        final decoded = jsonDecode(item);
        if (decoded is Map) {
          sources.add(SourceConfig.fromJson(decoded.cast<String, dynamic>()));
        }
      } catch (_) {
        // 单条脏数据不应导致整体读取失败 —— 静默跳过，由后续校验清理。
        continue;
      }
    }
    return sources;
  }

  Future<void> writeSources(List<SourceConfig> sources) async {
    final prefs = await _prefs;
    final encoded = sources
        .map((s) => jsonEncode(s.toJson()))
        .toList(growable: false);
    await prefs.setStringList(AppConstants.kSourcesKey, encoded);
  }

  // ── 订阅元信息 ──────────────────────────────────────────

  Future<List<SourceSubscription>> readSubscriptions() async {
    final prefs = await _prefs;
    final raw = prefs.getStringList(AppConstants.kSubscriptionsKey);
    if (raw == null || raw.isEmpty) return <SourceSubscription>[];

    final subscriptions = <SourceSubscription>[];
    for (final item in raw) {
      try {
        final decoded = jsonDecode(item);
        if (decoded is Map) {
          subscriptions.add(
            SourceSubscription.fromJson(decoded.cast<String, dynamic>()),
          );
        }
      } catch (_) {
        continue;
      }
    }
    return subscriptions;
  }

  Future<void> writeSubscriptions(List<SourceSubscription> subscriptions) async {
    final prefs = await _prefs;
    final encoded = subscriptions
        .map((s) => jsonEncode(s.toMetaJson()))
        .toList(growable: false);
    await prefs.setStringList(AppConstants.kSubscriptionsKey, encoded);
  }

  // ── 搜索历史 ────────────────────────────────────────────

  Future<List<String>> readSearchHistory() async {
    final prefs = await _prefs;
    return prefs.getStringList(AppConstants.kSearchHistoryKey) ?? <String>[];
  }

  Future<void> writeSearchHistory(List<String> history) async {
    final prefs = await _prefs;
    final trimmed = history.take(AppConstants.kSearchHistoryLimit).toList();
    await prefs.setStringList(AppConstants.kSearchHistoryKey, trimmed);
  }

  Future<void> clear() async {
    final prefs = await _prefs;
    await prefs.remove(AppConstants.kSourcesKey);
    await prefs.remove(AppConstants.kSubscriptionsKey);
  }
}

/// 仓储实现：组合本地数据源。
///
/// 说明：订阅包的**远程拉取**放在 `SourceRemoteDataSource`，
/// 本类通过构造函数注入，保持"本地/远程"职责分离。
class SourceRepositoryImpl implements SourceRepository {
  SourceRepositoryImpl({
    required SourceLocalDataSource local,
    required RemoteSubscriptionFetcher remote,
  })  : _local = local,
        _remote = remote;

  final SourceLocalDataSource _local;
  final RemoteSubscriptionFetcher _remote;

  @override
  Future<List<SourceConfig>> loadSources() => _local.readSources();

  @override
  Future<void> saveSources(List<SourceConfig> sources) =>
      _local.writeSources(sources);

  @override
  Future<(int added, int updated)> upsertSources(
    List<SourceConfig> sources,
  ) async {
    final existing = await _local.readSources();
    final index = <String, int>{
      for (var i = 0; i < existing.length; i++) existing[i].key: i,
    };

    var added = 0;
    var updated = 0;

    for (final incoming in sources) {
      final position = index[incoming.key];
      if (position == null) {
        index[incoming.key] = existing.length;
        existing.add(incoming);
        added++;
      } else {
        existing[position] = incoming;
        updated++;
      }
    }

    await _local.writeSources(existing);
    return (added, updated);
  }

  @override
  Future<void> removeSource(String key) async {
    final existing = await _local.readSources();
    existing.removeWhere((s) => s.key == key);
    await _local.writeSources(existing);
  }

  @override
  Future<List<SourceSubscription>> loadSubscriptions() =>
      _local.readSubscriptions();

  @override
  Future<void> saveSubscriptions(List<SourceSubscription> subscriptions) =>
      _local.writeSubscriptions(subscriptions);

  @override
  Future<SourceSubscription> fetchSubscription(String url, {String? etag}) =>
      _remote.fetch(url, etag: etag);

  @override
  SourceSubscription parseSubscription(String rawJson, {String url = ''}) =>
      _remote.parse(rawJson, url: url);

  @override
  Future<void> clear() => _local.clear();
}

/// 远程订阅获取契约。
///
/// 抽取为独立接口，便于在测试中用内存实现替换（无需真实网络）。
abstract class RemoteSubscriptionFetcher {
  Future<SourceSubscription> fetch(String url, {String? etag});
  SourceSubscription parse(String rawJson, {String url});
}
