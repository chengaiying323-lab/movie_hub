import 'dart:async';

import '../../core/error/exceptions.dart';
import '../../core/error/failure.dart';
import '../../core/network/http_service.dart';
import '../../core/utils/id_generator.dart';
import '../../core/utils/semaphore.dart';
import '../../core/utils/title_normalizer.dart';
import '../../domain/entities/movie.dart';
import '../../domain/entities/search_result.dart';
import '../../domain/entities/source_config.dart';
import '../mappers/failure_mapper.dart';
import '../parsers/parser_registry.dart';
import '../parsers/source_parser.dart';

/// 多源并发搜索与去重聚合服务。
///
/// 核心能力
/// ------------------------------------------------------------------
/// 1. **并发**：所有启用源同时发起请求，整体耗时 ≈ 最慢的源，
///    而非各源耗时之和；并发度由 [Semaphore] 限制，保护设备与源站。
/// 2. **隔离**：单源超时/报错/格式异常全部被捕获并转成 [SourceSearchReport]，
///    **绝不中断整体流程**——这是聚合类应用可用性的底线。
/// 3. **去重**：标题归一化（去标点/去画质后缀/去季集标记/全角转半角）
///    + 年份双重键分组，两轮合并解决「同片异名」问题。
/// 4. **聚合**：同一影片的多个源结果合并为一个 [AggregatedMovie]，
///    线路全部保留并按质量分排序，用户可在详情页自由切换。
/// 5. **可观测**：每源报告耗时、原始条数、过滤后条数、失败原因，
///    便于 UI 展示「哪些源挂了」以及后续做源质量排行。
class SearchAggregator {
  SearchAggregator({
    required HttpService http,
    required ParserRegistry registry,
    Semaphore? gate,
    int maxConcurrency = 10,
  })  : _http = http,
        _registry = registry,
        _gate = gate ?? Semaphore(maxConcurrency);

  final HttpService _http;
  final ParserRegistry _registry;
  final Semaphore _gate;

  /// 单次聚合搜索。
  ///
  /// [sources] 会被自动过滤（禁用 / 类型不支持），并按优先级排序；
  /// [maxSources] 用于「极速模式」只取优先级最高的前 N 个源。
  /// [enforceRelevance] 在关键词搜索时置 true，分类浏览时置 false。
  Future<AggregatedSearchResult> search(
    String keyword,
    List<SourceConfig> sources, {
    int page = 1,
    int? maxSources,
    bool enforceRelevance = true,
    Duration? timeout,
  }) async {
    final stopwatch = Stopwatch()..start();

    final targets = _selectTargets(sources, maxSources: maxSources);
    if (targets.isEmpty) {
      return AggregatedSearchResult(
        keyword: keyword,
        items: const <AggregatedMovie>[],
        reports: const <SourceSearchReport>[],
        totalElapsedMs: stopwatch.elapsedMilliseconds,
        page: page,
      );
    }

    // 并发执行，Future.wait 保证所有任务都被等待（异常已在内部吞掉）。
    final outcomes = await Future.wait(
      targets.map(
        (config) => _searchSingle(
          config: config,
          keyword: keyword,
          page: page,
          timeout: timeout,
        ),
      ),
    );

    stopwatch.stop();

    final reports = <SourceSearchReport>[];
    final collected = <Movie>[];
    for (final outcome in outcomes) {
      reports.add(outcome.report);
      collected.addAll(outcome.movies);
    }

    final items = _dedupeAndMerge(
      collected,
      keyword: keyword,
      enforceRelevance: enforceRelevance,
      priorityByKey: <String, int>{
        for (final s in targets) s.key: s.priority,
      },
    );

    return AggregatedSearchResult(
      keyword: keyword,
      items: items,
      reports: reports,
      totalElapsedMs: stopwatch.elapsedMilliseconds,
      page: page,
    );
  }

  /// 渐进式搜索：每完成一个源就推送一次**部分聚合结果**。
  ///
  /// 用于「秒出结果」体验——用户无需等待最慢的源。
  /// 消费方应在最后自行处理 `stream.done`。
  Stream<AggregatedSearchResult> searchStream(
    String keyword,
    List<SourceConfig> sources, {
    int page = 1,
    int? maxSources,
    bool enforceRelevance = true,
    Duration? timeout,
  }) {
    final controller = StreamController<AggregatedSearchResult>();
    final stopwatch = Stopwatch()..start();
    final targets = _selectTargets(sources, maxSources: maxSources);
    final priorityByKey = <String, int>{
      for (final s in targets) s.key: s.priority,
    };

    final completed = <_SourceOutcome>[];

    unawaited(() async {
      try {
        await Future.wait(
          targets.map((config) async {
            final outcome = await _searchSingle(
              config: config,
              keyword: keyword,
              page: page,
              timeout: timeout,
            );
            completed.add(outcome);

            final reports = completed.map((e) => e.report).toList();
            final movies = <Movie>[
              for (final item in completed) ...item.movies,
            ];

            controller.add(
              AggregatedSearchResult(
                keyword: keyword,
                items: _dedupeAndMerge(
                  movies,
                  keyword: keyword,
                  enforceRelevance: enforceRelevance,
                  priorityByKey: priorityByKey,
                ),
                reports: reports,
                totalElapsedMs: stopwatch.elapsedMilliseconds,
                page: page,
              ),
            );
          }),
        );
      } catch (error, stack) {
        controller.addError(error, stack);
      } finally {
        await controller.close();
      }
    }());

    return controller.stream;
  }

  /// 拉取详情并补全线路。
  ///
  /// 列表接口通常不含播放地址，进入详情页时才发起这次请求。
  Future<Movie> fetchDetail(
    SourceConfig config,
    String vodId, {
    Duration? timeout,
  }) async {
    final parser = _resolveParser(config);
    final url = config.buildDetailUrl(vodId);
    if (url == null) {
      throw SourceUnavailableFailure(
        '该数据源未配置详情端点',
        sourceKey: config.key,
      );
    }

    final payload = await _gate.run(
      () => _http.getJson(
        url,
        headers: config.headers,
        timeout: timeout ?? config.timeout,
      ),
    );

    final movie = parser.parseDetail(payload, config, fallbackId: vodId);
    if (movie == null) {
      throw SourceUnavailableFailure(
        '详情接口未返回有效数据（可能该资源已下架）',
        sourceKey: config.key,
      );
    }
    return movie;
  }

  // ── 内部实现 ────────────────────────────────────────────

  List<SourceConfig> _selectTargets(
    List<SourceConfig> sources, {
    int? maxSources,
  }) {
    final targets = sources
        .where((s) => s.enabled && s.searchable && s.kind.isClientSupported)
        .toList()
      ..sort((a, b) => a.priority.compareTo(b.priority));
    if (maxSources != null && maxSources > 0 && targets.length > maxSources) {
      return targets.sublist(0, maxSources);
    }
    return targets;
  }

  SourceParser _resolveParser(SourceConfig config) {
    if (!config.kind.isClientSupported) {
      throw UnsupportedSourceFailure(
        '数据源类型「${config.kind.wire}」需要外置解析运行时',
        sourceKey: config.key,
        kind: config.kind.wire,
      );
    }
    return _registry.resolve(config);
  }

  /// 单源搜索。**所有异常在此处被吞掉并转为报告**。
  Future<_SourceOutcome> _searchSingle({
    required SourceConfig config,
    required String keyword,
    required int page,
    Duration? timeout,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      final parser = _resolveParser(config);
      final url = config.buildSearchUrl(keyword, page: page);
      if (url == null) {
        throw SourceParseException('该数据源未配置搜索端点', sourceKey: config.key);
      }

      final effectiveTimeout = timeout ?? config.timeout;

      // 双重超时保护：
      // 1) Dio 的 connect/receive 超时（帧级）；
      // 2) 外层兜底超时（防止 Future 因未知原因永久挂起）。
      final payload = await _gate
          .run(
            () => _http.getJson(
              url,
              headers: config.headers,
              timeout: effectiveTimeout,
            ),
          )
          .timeout(effectiveTimeout * 2);

      final movies = parser.parseList(payload, config);
      stopwatch.stop();

      return _SourceOutcome(
        report: SourceSearchReport(
          sourceKey: config.key,
          sourceName: config.name,
          ok: true,
          rawCount: movies.length,
          keptCount: movies.length,
          elapsedMs: stopwatch.elapsedMilliseconds,
        ),
        movies: movies,
      );
    } catch (error) {
      stopwatch.stop();
      final failure = FailureMapper.map(error, source: config);
      return _SourceOutcome(
        report: SourceSearchReport.failure(
          sourceKey: config.key,
          sourceName: config.name,
          errorType: failure.runtimeType.toString(),
          errorMessage: failure.message,
          elapsedMs: stopwatch.elapsedMilliseconds,
        ),
        movies: const <Movie>[],
      );
    }
  }

  /// 相关性过滤 + 两轮去重 + 聚合。
  List<AggregatedMovie> _dedupeAndMerge(
    List<Movie> movies, {
    required String keyword,
    required bool enforceRelevance,
    required Map<String, int> priorityByKey,
  }) {
    if (movies.isEmpty) return const <AggregatedMovie>[];

    // ── 第一轮：相关性过滤 ────────────────────────────────
    // 苹果CMS 的模糊搜索会返回大量无关条目，必须过滤，否则聚合结果噪声极大。
    final filtered = <Movie>[];
    for (final movie in movies) {
      if (enforceRelevance &&
          keyword.trim().isNotEmpty &&
          !TitleNormalizer.isRelevant(keyword, movie.title)) {
        continue;
      }
      filtered.add(movie);
    }
    if (filtered.isEmpty) return const <AggregatedMovie>[];

    // ── 第二轮：精确键分组（归一化标题 + 年份） ────────────
    final exactGroups = <String, List<Movie>>{};
    for (final movie in filtered) {
      exactGroups.putIfAbsent(_exactKey(movie), () => <Movie>[]).add(movie);
    }

    // ── 第三轮：宽松键合并 ────────────────────────────────
    // 解决「沙丘2」与「沙丘：第二部」这类同片异名无法命中精确键的问题。
    final looseGroups = <String, List<Movie>>{};
    for (final group in exactGroups.values) {
      looseGroups.putIfAbsent(_looseKey(group.first), () => <Movie>[]).addAll(group);
    }

    // ── 聚合 ──────────────────────────────────────────────
    final aggregated = <AggregatedMovie>[];
    for (final group in looseGroups.values) {
      final sorted = [...group]..sort(
          (a, b) => _compareVariants(a, b, priorityByKey),
        );
      aggregated.add(
        AggregatedMovie(
          primary: sorted.first,
          variants: List<Movie>.unmodifiable(sorted),
        ),
      );
    }

    // ── 排序：源越多越靠前 → 有线路数据优先 → 标题字典序 ────
    aggregated.sort((a, b) {
      final bySourceCount = b.sourceCount.compareTo(a.sourceCount);
      if (bySourceCount != 0) return bySourceCount;

      final byLineData =
          (b.hasLineData ? 1 : 0).compareTo(a.hasLineData ? 1 : 0);
      if (byLineData != 0) return byLineData;

      return a.primary.title.compareTo(b.primary.title);
    });

    return List<AggregatedMovie>.unmodifiable(aggregated);
  }

  /// 精确去重键：归一化标题 + 年份。
  static String _exactKey(Movie movie) => IdGenerator.dedupeKey(
        TitleNormalizer.normalize(movie.title),
        movie.year ?? TitleNormalizer.extractYear(movie.title),
      );

  /// 宽松去重键：在精确键基础上去掉结尾数字（季数/续集序号）。
  static String _looseKey(Movie movie) {
    final normalized =
        TitleNormalizer.normalize(movie.title).replaceAll(RegExp(r'\d+$'), '');
    return IdGenerator.dedupeKey(
      normalized.isEmpty ? TitleNormalizer.normalize(movie.title) : normalized,
      movie.year ?? TitleNormalizer.extractYear(movie.title),
    );
  }

  /// 变体排序：源优先级 → 元数据完整度 → ID（保证排序稳定）。
  static int _compareVariants(
    Movie a,
    Movie b,
    Map<String, int> priorityByKey,
  ) {
    final byPriority = (priorityByKey[a.sourceKey] ?? 999)
        .compareTo(priorityByKey[b.sourceKey] ?? 999);
    if (byPriority != 0) return byPriority;

    final bySourceData = (b.sources.isNotEmpty ? 1 : 0)
        .compareTo(a.sources.isNotEmpty ? 1 : 0);
    if (bySourceData != 0) return bySourceData;

    final byEpisodes = b.totalEpisodes.compareTo(a.totalEpisodes);
    if (byEpisodes != 0) return byEpisodes;

    return a.id.compareTo(b.id);
  }
}

/// 单源搜索的原始产出（内部使用）。
class _SourceOutcome {
  const _SourceOutcome({required this.report, required this.movies});

  final SourceSearchReport report;
  final List<Movie> movies;
}
