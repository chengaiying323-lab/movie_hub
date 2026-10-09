import '../entities/search_result.dart';
import '../repositories/movie_repository.dart';

/// 用例：多源聚合搜索。
///
/// 用例层存在的意义：把「一次用户动作」对应到的业务规则集中表达，
/// 例如关键词预处理、结果空态判定等，避免这些规则散落在 Widget 中。
/// 同时它是 presentation 层唯一可直接依赖的 domain 入口。
class SearchMoviesUseCase {
  const SearchMoviesUseCase(this._repository);

  final MovieRepository _repository;

  /// 执行搜索。
  ///
  /// [quickMode] 为 true 时只查询优先级最高的前 N 个源（"极速模式"）。
  Future<AggregatedSearchResult> call(
    String keyword, {
    int page = 1,
    bool quickMode = false,
    bool enforceRelevance = true,
  }) {
    final normalized = _normalizeKeyword(keyword);
    return _repository.aggregateSearch(
      normalized,
      page: page,
      maxSources: quickMode ? 5 : null,
      enforceRelevance: enforceRelevance,
    );
  }

  /// 渐进式搜索，用于"秒出结果"体验。
  Stream<AggregatedSearchResult> stream(
    String keyword, {
    int page = 1,
    bool quickMode = false,
  }) {
    return _repository.aggregateSearchStream(
      _normalizeKeyword(keyword),
      page: page,
      maxSources: quickMode ? 5 : null,
    );
  }

  static String _normalizeKeyword(String keyword) =>
      keyword.trim().replaceAll(RegExp(r'\s+'), ' ');
}
