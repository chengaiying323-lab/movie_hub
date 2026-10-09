import '../../core/error/exceptions.dart';
import '../../core/error/failure.dart';
import '../../core/network/http_service.dart';
import '../../core/utils/semaphore.dart';
import '../../domain/entities/movie.dart';
import '../../domain/entities/search_result.dart';
import '../../domain/entities/source_config.dart';
import '../../domain/repositories/movie_repository.dart';
import '../../domain/repositories/source_repository.dart';
import '../mappers/failure_mapper.dart';
import '../parsers/parser_registry.dart';
import '../services/search_aggregator.dart';

/// 影视数据仓储实现。
///
/// 职责：把 domain 层的语义化调用，翻译为「读源配置 → 拼端点 → 发请求 → 解析」，
/// 并把所有底层异常收敛为 [Failure]。
class MovieRepositoryImpl implements MovieRepository {
  MovieRepositoryImpl({
    required SourceRepository sourceRepository,
    required SearchAggregator aggregator,
    required ParserRegistry registry,
    required HttpService http,
    Semaphore? browseGate,
  })  : _sourceRepository = sourceRepository,
        _aggregator = aggregator,
        _registry = registry,
        _http = http,
        _browseGate = browseGate ?? Semaphore(4);

  final SourceRepository _sourceRepository;
  final SearchAggregator _aggregator;
  final ParserRegistry _registry;
  final HttpService _http;
  final Semaphore _browseGate;

  @override
  Future<AggregatedSearchResult> aggregateSearch(
    String keyword, {
    int page = 1,
    int? maxSources,
    bool enforceRelevance = true,
  }) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return AggregatedSearchResult.empty(trimmed);

    try {
      final sources = await _sourceRepository.loadSources();
      return await _aggregator.search(
        trimmed,
        sources,
        page: page,
        maxSources: maxSources,
        enforceRelevance: enforceRelevance,
      );
    } catch (error) {
      throw FailureMapper.map(error);
    }
  }

  @override
  Stream<AggregatedSearchResult> aggregateSearchStream(
    String keyword, {
    int page = 1,
    int? maxSources,
  }) async* {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) {
      yield AggregatedSearchResult.empty(trimmed);
      return;
    }
    final sources = await _sourceRepository.loadSources();
    yield* _aggregator.searchStream(
      trimmed,
      sources,
      page: page,
      maxSources: maxSources,
    );
  }

  @override
  Future<Movie> fetchDetail({
    required String sourceKey,
    required String vodId,
  }) async {
    try {
      final sources = await _sourceRepository.loadSources();
      final config = _findConfig(sources, sourceKey);

      if (!config.detailable) {
        throw SourceUnavailableFailure(
          '数据源「${config.name}」不支持详情查询',
          sourceKey: sourceKey,
        );
      }
      return await _aggregator.fetchDetail(config, vodId);
    } catch (error) {
      throw FailureMapper.map(error);
    }
  }

  @override
  Future<List<Movie>> browseCategory({
    required String sourceKey,
    required String typeId,
    int page = 1,
  }) async {
    try {
      final sources = await _sourceRepository.loadSources();
      final config = _findConfig(sources, sourceKey);

      final parser = _registry.resolve(config);
      final url = config.buildCategoryUrl(typeId, page: page);
      if (url == null) {
        throw SourceUnavailableFailure(
          '数据源「${config.name}」未配置分类端点',
          sourceKey: sourceKey,
        );
      }

      final payload = await _browseGate.run(
        () => _http.getJson(url, headers: config.headers, timeout: config.timeout),
      );
      return parser.parseList(payload, config);
    } catch (error) {
      throw FailureMapper.map(error);
    }
  }

  SourceConfig _findConfig(List<SourceConfig> sources, String sourceKey) {
    for (final config in sources) {
      if (config.key == sourceKey) return config;
    }
    throw SourceConfigException('数据源不存在或已被移除：$sourceKey');
  }
}
