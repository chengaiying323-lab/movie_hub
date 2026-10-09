import '../entities/movie.dart';
import '../entities/search_result.dart';

/// 影视数据仓储接口（domain 层声明）。
///
/// presentation 层只依赖本接口，不感知 Dio / 解析器 / 本地存储的实现细节。
abstract class MovieRepository {
  /// 多源聚合搜索。
  Future<AggregatedSearchResult> aggregateSearch(
    String keyword, {
    int page,
    int? maxSources,
    bool enforceRelevance,
  });

  /// 渐进式聚合搜索（每完成一个源推送一次部分结果）。
  Stream<AggregatedSearchResult> aggregateSearchStream(
    String keyword, {
    int page,
    int? maxSources,
  });

  /// 拉取指定源的影片详情（含完整线路与选集）。
  Future<Movie> fetchDetail({
    required String sourceKey,
    required String vodId,
  });

  /// 按分类浏览（首页各频道使用）。
  Future<List<Movie>> browseCategory({
    required String sourceKey,
    required String typeId,
    int page,
  });
}
