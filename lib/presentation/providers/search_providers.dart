import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/movie.dart';
import '../../domain/entities/search_result.dart';
import 'core_providers.dart';

/// 当前搜索关键词。
final searchQueryProvider = StateProvider<String>((ref) => '');

/// 极速模式（只查优先级最高的 5 个源）。
final quickSearchProvider = StateProvider<bool>((ref) => false);

/// 是否使用渐进式流式搜索（边搜边出结果）。
final progressiveSearchProvider = StateProvider<bool>((ref) => true);

/// 搜索流是否仍在进行中（用于结果区顶部的细进度条）。
///
/// 单独成 Provider 而不塞进 AsyncValue：流式搜索过程中 state 会被
/// 反复写入 data，若用 loading 表达"进行中"会导致内容闪烁。
final searchStreamingProvider = StateProvider<bool>((ref) => false);

/// 当前选中的分源过滤（null = 全部源）。
final selectedSourceFilterProvider = StateProvider<String?>((ref) => null);

/// 搜索结果状态。
final searchResultProvider =
    AsyncNotifierProvider<SearchNotifier, AggregatedSearchResult?>(
  SearchNotifier.new,
);

class SearchNotifier extends AsyncNotifier<AggregatedSearchResult?> {
  @override
  Future<AggregatedSearchResult?> build() async => null;

  /// 执行一次聚合搜索。
  ///
  /// [progressive] 为 true 时使用 `searchStream`：每完成一个源就刷新一次 UI，
  /// 用户无需等待最慢的源 —— 这是聚合类应用体验差异最大的一个点。
  Future<void> search(
    String keyword, {
    bool? quickMode,
    bool? progressive,
  }) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) {
      state = const AsyncValue.data(null);
      return;
    }

    final useQuick = quickMode ?? ref.read(quickSearchProvider);
    final useProgressive = progressive ?? ref.read(progressiveSearchProvider);
    final useCase = ref.read(searchMoviesUseCaseProvider);

    // 新一轮搜索重置分源过滤
    ref.read(selectedSourceFilterProvider.notifier).state = null;
    ref.read(searchStreamingProvider.notifier).state = true;
    state = const AsyncValue.loading();

    try {
      if (!useProgressive) {
        final result = await useCase(trimmed, quickMode: useQuick);
        state = AsyncValue.data(result);
      } else {
        await for (final partial
            in useCase.stream(trimmed, quickMode: useQuick)) {
          state = AsyncValue.data(partial);
        }
      }
      await ref.read(searchHistoryProvider.notifier).push(trimmed);
    } catch (error, stack) {
      state = AsyncValue.error(error, stack);
    } finally {
      ref.read(searchStreamingProvider.notifier).state = false;
    }
  }

  void clear() {
    state = const AsyncValue.data(null);
    ref.read(selectedSourceFilterProvider.notifier).state = null;
    ref.read(searchStreamingProvider.notifier).state = false;
  }
}

// ── 分源 Tab ────────────────────────────────────────────────

/// 分源过滤选项（搜索页顶部 Tab）。
class SourceFilterOption {
  const SourceFilterOption({
    required this.sourceKey,
    required this.name,
    required this.count,
    required this.ok,
    this.errorMessage,
    this.elapsedMs = 0,
  });

  /// null 表示「全部」。
  final String? sourceKey;
  final String name;

  /// 该源贡献的结果条数。
  final int count;

  final bool ok;
  final String? errorMessage;
  final int elapsedMs;

  bool get isAll => sourceKey == null;

  String get label => isAll ? '全部 ($count)' : '$name ($count)';
}

/// 由当前搜索结果派生出分源 Tab 列表。
final sourceFilterOptionsProvider = Provider<List<SourceFilterOption>>((ref) {
  final result = ref.watch(searchResultProvider).valueOrNull;
  if (result == null) return const <SourceFilterOption>[];

  final options = <SourceFilterOption>[
    SourceFilterOption(
      sourceKey: null,
      name: '全部',
      count: result.items.length,
      ok: true,
      elapsedMs: result.totalElapsedMs,
    ),
  ];

  for (final report in result.reports) {
    final count = result.items
        .where((item) => item.variants.any((v) => v.sourceKey == report.sourceKey))
        .length;
    options.add(
      SourceFilterOption(
        sourceKey: report.sourceKey,
        name: report.sourceName,
        count: count,
        ok: report.ok,
        errorMessage: report.errorMessage,
        elapsedMs: report.elapsedMs,
      ),
    );
  }

  // 失败的源排到最后，避免占据显眼位置
  options.sort((a, b) {
    if (a.isAll) return -1;
    if (b.isAll) return 1;
    if (a.ok != b.ok) return a.ok ? -1 : 1;
    return b.count.compareTo(a.count);
  });
  return options;
});

/// 应用分源过滤后的结果条目。
///
/// 过滤时把 `primary` 换成该源的变体，保证卡片上的「来源」角标
/// 与用户所选 Tab 一致。
final filteredSearchItemsProvider = Provider<List<AggregatedMovie>>((ref) {
  final result = ref.watch(searchResultProvider).valueOrNull;
  if (result == null) return const <AggregatedMovie>[];

  final filterKey = ref.watch(selectedSourceFilterProvider);
  if (filterKey == null) return result.items;

  final filtered = <AggregatedMovie>[];
  for (final item in result.items) {
    final variant =
        item.variants.firstWhereOrNull((v) => v.sourceKey == filterKey);
    if (variant == null) continue;
    filtered.add(AggregatedMovie(primary: variant, variants: <Movie>[variant]));
  }
  return filtered;
});

// ── 搜索历史 ────────────────────────────────────────────────

/// 搜索历史（本地持久化，最多 `AppConstants.kSearchHistoryLimit` 条）。
final searchHistoryProvider =
    AsyncNotifierProvider<SearchHistoryNotifier, List<String>>(
  SearchHistoryNotifier.new,
);

class SearchHistoryNotifier extends AsyncNotifier<List<String>> {
  @override
  Future<List<String>> build() async {
    return ref.read(sourceLocalDataSourceProvider).readSearchHistory();
  }

  /// 记录一次搜索（去重后置顶）。
  Future<void> push(String keyword) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return;

    final current = state.valueOrNull ?? const <String>[];
    final next = <String>[
      trimmed,
      ...current.where((e) => e != trimmed),
    ];

    state = AsyncValue.data(next);
    await ref.read(sourceLocalDataSourceProvider).writeSearchHistory(next);
  }

  Future<void> remove(String keyword) async {
    final current = state.valueOrNull ?? const <String>[];
    final next = current.where((e) => e != keyword).toList(growable: false);
    state = AsyncValue.data(next);
    await ref.read(sourceLocalDataSourceProvider).writeSearchHistory(next);
  }

  Future<void> clear() async {
    state = const AsyncValue.data(<String>[]);
    await ref.read(sourceLocalDataSourceProvider).writeSearchHistory(<String>[]);
  }
}

// ── 详情 ────────────────────────────────────────────────────

/// 选中影片的详情（按 `sourceKey:vodId` 分家族）。
///
/// 使用 family 而非单一状态：桌面端用户可能同时打开多个详情页
/// （例如左右分栏对比不同源）。
final movieDetailProvider =
    AsyncNotifierProvider.family<MovieDetailNotifier, Movie, MovieRequest>(
  MovieDetailNotifier.new,
);

class MovieDetailNotifier extends FamilyAsyncNotifier<Movie, MovieRequest> {
  @override
  Future<Movie> build(MovieRequest arg) async {
    return ref.read(getMovieDetailUseCaseProvider)(
      sourceKey: arg.sourceKey,
      vodId: arg.vodId,
      seed: arg.seed,
    );
  }

  Future<void> reload() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(getMovieDetailUseCaseProvider)(
        sourceKey: arg.sourceKey,
        vodId: arg.vodId,
        seed: null,
      ),
    );
  }
}

/// 详情请求参数（值对象，用于 family 相等性判定）。
class MovieRequest {
  const MovieRequest({
    required this.sourceKey,
    required this.vodId,
    this.seed,
  });

  final String sourceKey;
  final String vodId;

  /// 列表页带过来的轻量条目，可避免重复请求详情。
  final Movie? seed;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MovieRequest &&
          other.sourceKey == sourceKey &&
          other.vodId == vodId;

  @override
  int get hashCode => Object.hash(sourceKey, vodId);
}
