import 'package:meta/meta.dart';

import 'movie.dart';

/// 首页推荐分区（横向滑动栏的数据载体）。
@immutable
class HomeSection {
  const HomeSection({
    required this.id,
    required this.title,
    required this.sourceKey,
    required this.sourceName,
    required this.typeId,
    required this.movies,
    this.subtitle,
  });

  /// 稳定标识，用作 Widget key。
  final String id;

  final String title;
  final String? subtitle;

  /// 该分区数据实际来自哪个源（用于容错后溯源）。
  final String sourceKey;
  final String sourceName;

  /// 源站分类 ID。
  final String typeId;

  final List<Movie> movies;

  bool get isEmpty => movies.isEmpty;

  HomeSection copyWith({List<Movie>? movies, String? sourceKey, String? sourceName}) =>
      HomeSection(
        id: id,
        title: title,
        subtitle: subtitle,
        sourceKey: sourceKey ?? this.sourceKey,
        sourceName: sourceName ?? this.sourceName,
        typeId: typeId,
        movies: movies ?? this.movies,
      );
}

/// 首页聚合数据。
@immutable
class HomeFeed {
  const HomeFeed({
    required this.banners,
    required this.sections,
    required this.sourceKey,
    required this.sourceName,
    required this.loadedAt,
    this.warnings = const <String>[],
  });

  /// 顶部焦点图候选（优先取有横版剧照的条目）。
  final List<Movie> banners;

  /// 推荐分区。
  final List<HomeSection> sections;

  /// 实际提供数据的主源。
  final String sourceKey;
  final String sourceName;

  final DateTime loadedAt;

  /// 加载过程中的降级信息（哪些源失败、哪些分区被跳过）。
  final List<String> warnings;

  bool get isEmpty => banners.isEmpty && sections.every((s) => s.isEmpty);

  /// 首页是否没有可用数据源。
  bool get hasNoSource => sourceKey.isEmpty;

  static HomeFeed none() => HomeFeed(
        banners: const <Movie>[],
        sections: const <HomeSection>[],
        sourceKey: '',
        sourceName: '',
        loadedAt: DateTime.now(),
      );

  @override
  String toString() =>
      'HomeFeed(banners=${banners.length}, sections=${sections.length}, source=$sourceName)';
}

/// 首页分区定义。
@immutable
class HomeSectionDefinition {
  const HomeSectionDefinition({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.typeId,
  });

  final String id;
  final String title;
  final String? subtitle;

  /// 苹果CMS 约定分类 ID（1=电影 2=连续剧 3=综艺 4=动漫）。
  ///
  /// 注意：少数站点自定义了分类体系，此时该分区请求会返回空或失败，
  /// 由 [HomeFeedService] 静默跳过，不影响其它分区。
  final String typeId;
}
