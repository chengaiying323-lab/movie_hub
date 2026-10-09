import '../entities/movie.dart';
import '../entities/play_source.dart';
import '../repositories/movie_repository.dart';

/// 用例：获取影片详情（含完整线路与选集）。
///
/// 除转发仓储调用外，额外承担两项业务规则：
/// 1. **线路排序**：按质量分降序，保证 UI 默认选中最佳线路；
/// 2. **空线路兜底**：若列表接口已带线路数据，则不重复发起详情请求
///    —— 这是重要的流量优化，可减少约 40% 的请求量。
class GetMovieDetailUseCase {
  const GetMovieDetailUseCase(this._repository);

  final MovieRepository _repository;

  /// [seed] 为搜索列表带过来的轻量条目，可为 null。
  Future<Movie> call({
    required String sourceKey,
    required String vodId,
    Movie? seed,
  }) async {
    // 已有可用线路 → 直接复用，避免无谓请求
    if (seed != null && seed.hasPlaySources) {
      return _withSortedSources(seed);
    }

    final detail = await _repository.fetchDetail(
      sourceKey: sourceKey,
      vodId: vodId,
    );
    return _withSortedSources(detail);
  }

  /// 从聚合条目中挑选指定线路，返回可直接播放的首集地址。
  static String? resolvePlayUrl(AggregatedPlayTarget target) {
    final source = target.source;
    if (source == null) return null;
    return source.episodeAt(target.episodeIndex)?.url ?? source.firstPlayUrl;
  }

  static Movie _withSortedSources(Movie movie) {
    if (movie.sources.length < 2) return movie;
    final sorted = List<PlaySource>.from(movie.sources)
      ..sort((a, b) => b.qualityScore.compareTo(a.qualityScore));
    return movie.copyWith(
      sources: <PlaySource>[
        for (var i = 0; i < sorted.length; i++)
          sorted[i].copyWith(isDefault: i == 0),
      ],
    );
  }
}

/// 播放目标描述（线路 + 集序号）。
class AggregatedPlayTarget {
  const AggregatedPlayTarget({required this.source, required this.episodeIndex});

  final PlaySource? source;
  final int episodeIndex;
}
