import 'package:meta/meta.dart';

import 'movie.dart';
import 'play_source.dart';

/// 聚合后的影视条目。
///
/// 多源搜索的核心产物：同一部影片在 N 个源站的结果被合并为一个条目，
/// 各源站的线路全部挂载在 [variants] 上，用户可在详情页自由切换线路。
@immutable
class AggregatedMovie {
  const AggregatedMovie({
    required this.primary,
    required this.variants,
  });

  /// 主条目：聚合层按「优先级 + 线路质量」挑选的最佳代表。
  final Movie primary;

  /// 参与聚合的全部原始条目（含 primary 自身）。
  final List<Movie> variants;

  /// 全部可选线路（跨源合并）。
  ///
  /// 去重策略：以 `flag + 首集地址` 为键，避免同一线路重复出现。
  List<PlaySource> get allSources {
    final seen = <String>{};
    final result = <PlaySource>[];
    for (final variant in variants) {
      for (final source in variant.sources) {
        final dedupeKey = '${source.flag}|${source.firstPlayUrl ?? source.episodeCount}';
        if (seen.add(dedupeKey)) {
          result.add(source);
        }
      }
    }
    result.sort((a, b) => b.qualityScore.compareTo(a.qualityScore));
    return result;
  }

  /// 可用源站数量。
  int get sourceCount => variants.length;

  /// 最优线路。
  PlaySource? get bestSource {
    final sources = allSources;
    return sources.isEmpty ? null : sources.first;
  }

  /// 主条目是否已加载线路数据（列表接口通常为空，需进详情页补全）。
  bool get hasLineData => variants.any((v) => v.sources.isNotEmpty);

  /// 合并后的展示元数据（取各变体中信息最全的一份）。
  Movie get merged {
    Movie best = primary;
    var bestScore = _completeness(best);
    for (final v in variants) {
      final s = _completeness(v);
      if (s > bestScore) {
        best = v;
        bestScore = s;
      }
    }
    return best.copyWith(
      sources: allSources,
      sourceKey: primary.sourceKey,
      sourceName: sourceCount > 1
          ? '${primary.sourceName} 等 $sourceCount 个源'
          : primary.sourceName,
    );
  }

  static int _completeness(Movie movie) {
    var score = 0;
    if (movie.poster.isNotEmpty) score += 3;
    if ((movie.description ?? '').trim().isNotEmpty) score += 2;
    if (movie.year != null) score += 1;
    if (movie.score != null) score += 1;
    if (movie.categories.isNotEmpty) score += 1;
    if (movie.sources.isNotEmpty) score += 2;
    score += movie.totalEpisodes ~/ 10;
    return score;
  }

  @override
  String toString() =>
      'AggregatedMovie(${primary.title}, 源=$sourceCount, 线路=${allSources.length})';
}

/// 单源搜索执行报告。
///
/// 多源聚合必须向用户**透明暴露每个源的状态**——哪些源失败、耗时多少，
/// 否则用户只会看到"结果变少了"却无法判断是源挂了还是客户端有问题。
@immutable
class SourceSearchReport {
  const SourceSearchReport({
    required this.sourceKey,
    required this.sourceName,
    required this.ok,
    required this.rawCount,
    required this.keptCount,
    required this.elapsedMs,
    this.errorMessage,
    this.errorType,
  });

  final String sourceKey;
  final String sourceName;
  final bool ok;

  /// 源站原始返回条数（过滤前）。
  final int rawCount;

  /// 通过相关性过滤后保留的条数。
  final int keptCount;

  final int elapsedMs;
  final String? errorMessage;

  /// 错误类型名（`TimeoutFailure` / `ParseFailure` / ...），便于分类统计。
  final String? errorType;

  factory SourceSearchReport.failure({
    required String sourceKey,
    required String sourceName,
    required String errorType,
    required String errorMessage,
    required int elapsedMs,
  }) =>
      SourceSearchReport(
        sourceKey: sourceKey,
        sourceName: sourceName,
        ok: false,
        rawCount: 0,
        keptCount: 0,
        elapsedMs: elapsedMs,
        errorMessage: errorMessage,
        errorType: errorType,
      );

  @override
  String toString() => ok
      ? 'SourceSearchReport($sourceKey, ok, ${keptCount}/${rawCount}, ${elapsedMs}ms)'
      : 'SourceSearchReport($sourceKey, FAIL[$errorType], ${elapsedMs}ms)';
}

/// 聚合搜索结果。
@immutable
class AggregatedSearchResult {
  const AggregatedSearchResult({
    required this.keyword,
    required this.items,
    required this.reports,
    required this.totalElapsedMs,
    required this.page,
  });

  final String keyword;
  final List<AggregatedMovie> items;

  /// 每个源的执行报告（成功与失败都在内）。
  final List<SourceSearchReport> reports;

  final int totalElapsedMs;
  final int page;

  int get successCount => reports.where((r) => r.ok).length;
  int get failureCount => reports.length - successCount;

  bool get isEmpty => items.isEmpty;

  /// 失败的源（UI 上可折叠展示，供用户手动关闭劣质源）。
  List<SourceSearchReport> get failedReports =>
      reports.where((r) => !r.ok).toList(growable: false);

  static AggregatedSearchResult empty(String keyword) => AggregatedSearchResult(
        keyword: keyword,
        items: const <AggregatedMovie>[],
        reports: const <SourceSearchReport>[],
        totalElapsedMs: 0,
        page: 1,
      );

  @override
  String toString() =>
      'AggregatedSearchResult("$keyword", ${items.length} 条, '
      '${successCount}成功/${failureCount}失败, ${totalElapsedMs}ms)';
}
