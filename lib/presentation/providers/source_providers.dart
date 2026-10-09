import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/source_config.dart';
import '../../domain/entities/source_validation.dart';
import 'core_providers.dart';

/// 数据源列表状态。
///
/// 使用 AsyncNotifier 而非 StateNotifier：源的加载/校验本身就是异步过程，
/// AsyncValue 天然表达 loading / error / data 三态，避免手写 isLoading 标志位。
final sourcesProvider =
    AsyncNotifierProvider<SourcesNotifier, List<SourceConfig>>(
  SourcesNotifier.new,
);

/// 按 key 查数据源配置（同步；加载中或未命中返回 null）。
///
/// 播放层需要它来推导防盗链请求头：UA / Referer / Cookie 全在源配置里，
/// 拿不到配置就只能用兜底头，很多带白名单校验的直链会直接 403。
final sourceConfigByKeyProvider = Provider.family<SourceConfig?, String>(
  (ref, key) {
    final list = ref.watch(sourcesProvider).valueOrNull;
    if (list == null) return null;
    for (final config in list) {
      if (config.key == key) return config;
    }
    return null;
  },
);

class SourcesNotifier extends AsyncNotifier<List<SourceConfig>> {
  @override
  Future<List<SourceConfig>> build() async {
    return ref.read(sourceManagerProvider).loadSources();
  }

  Future<void> reload() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(sourceManagerProvider).loadSources(),
    );
  }

  /// 从订阅地址导入，并刷新列表。
  Future<SourceImportReport> importFromUrl(String url) async {
    final manager = ref.read(sourceManagerProvider);
    final report = await manager.importFromUrl(url);
    await reload();
    return report;
  }

  /// 从原始 JSON 导入。
  Future<SourceImportReport> importFromRaw(String rawJson) async {
    final manager = ref.read(sourceManagerProvider);
    final report = await manager.importFromRaw(rawJson);
    await reload();
    return report;
  }

  Future<void> toggle(String key, bool enabled) async {
    // 乐观更新：先改 UI，再落盘；失败则回滚。
    final previous = state.valueOrNull ?? const <SourceConfig>[];
    state = AsyncValue.data(<SourceConfig>[
      for (final s in previous) s.key == key ? s.copyWith(enabled: enabled) : s,
    ]);
    try {
      await ref.read(sourceManagerProvider).setEnabled(key, enabled);
    } catch (error, stack) {
      state = AsyncValue.data(previous);
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<void> remove(String key) async {
    await ref.read(sourceManagerProvider).remove(key);
    await reload();
  }

  Future<void> setPriority(String key, int priority) async {
    await ref.read(sourceManagerProvider).setPriority(key, priority);
    await reload();
  }

  Future<void> validateOne(SourceConfig config) async {
    await ref.read(sourceValidationProvider(config).notifier).run();
  }
}

/// 单源校验状态（按源 key 分家族）。
final sourceValidationProvider = AsyncNotifierProvider.family<
    SourceValidationNotifier, SourceValidationResult?, SourceConfig>(
  SourceValidationNotifier.new,
);

class SourceValidationNotifier
    extends FamilyAsyncNotifier<SourceValidationResult?, SourceConfig> {
  @override
  Future<SourceValidationResult?> build(SourceConfig arg) async => null;

  Future<void> run() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(sourceManagerProvider).validate(arg),
    );
  }
}

/// 批量校验结果（按源 key 索引）。
final bulkValidationProvider =
    StateProvider<Map<String, SourceValidationResult>>((ref) => const {});

/// 订阅元信息列表。
final subscriptionsProvider =
    AsyncNotifierProvider<SubscriptionsNotifier, List<SourceSubscription>>(
  SubscriptionsNotifier.new,
);

class SubscriptionsNotifier extends AsyncNotifier<List<SourceSubscription>> {
  @override
  Future<List<SourceSubscription>> build() async {
    return ref.read(sourceManagerProvider).loadSubscriptions();
  }

  Future<void> reload() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(sourceManagerProvider).loadSubscriptions(),
    );
  }

  /// 检查更新，返回可更新的订阅数量。
  Future<int> checkUpdates() async {
    final updates = await ref.read(sourceManagerProvider).checkUpdates();
    return updates.length;
  }

  Future<SourceImportReport> refresh(String subscriptionId) async {
    final report =
        await ref.read(sourceManagerProvider).refreshSubscription(subscriptionId);
    await reload();
    ref.invalidate(sourcesProvider);
    return report;
  }
}

/// 便捷派生：已启用的源数量。
final enabledSourceCountProvider = Provider<int>((ref) {
  final sources = ref.watch(sourcesProvider).valueOrNull;
  if (sources == null) return 0;
  return sources.where((s) => s.enabled && s.kind.isClientSupported).length;
});
