import '../../core/error/failure.dart';
import '../../domain/entities/home_feed.dart';
import '../../domain/entities/movie.dart';
import '../../domain/entities/source_config.dart';
import '../../domain/repositories/movie_repository.dart';
import '../../domain/repositories/source_repository.dart';

/// 首页数据装配服务。
///
/// 设计要点
/// ------------------------------------------------------------------
/// 1. **不新增后端接口**：首页数据完全由「分类浏览」接口拼装而成，
///    复用第一阶段已有的 `browseCategory`，避免为首页引入私有协议。
/// 2. **主源 + 降级链**：优先使用优先级最高且支持分类的源；
///    若该源某分区失败，自动降级到下一个候选源，而不是整页白屏。
/// 3. **分区独立容错**：任一分区失败只影响该分区，其余照常展示。
class HomeFeedService {
  HomeFeedService({
    required MovieRepository movieRepository,
    required SourceRepository sourceRepository,
  })  : _movieRepository = movieRepository,
        _sourceRepository = sourceRepository;

  final MovieRepository _movieRepository;
  final SourceRepository _sourceRepository;

  /// 首页分区定义（苹果CMS 通用分类 ID）。
  static const List<HomeSectionDefinition> sections =
      <HomeSectionDefinition>[
    HomeSectionDefinition(
      id: 'movie',
      title: '热门电影',
      subtitle: '正在被大量观看',
      typeId: '1',
    ),
    HomeSectionDefinition(
      id: 'tv',
      title: '连续剧集',
      subtitle: '追更不迷路',
      typeId: '2',
    ),
    HomeSectionDefinition(
      id: 'variety',
      title: '综艺娱乐',
      subtitle: '轻松一刻',
      typeId: '3',
    ),
    HomeSectionDefinition(
      id: 'anime',
      title: '动漫番剧',
      subtitle: '新番速递',
      typeId: '4',
    ),
  ];

  /// 单分区最多保留的条目数（横向栏不需要更多）。
  static const int _sectionLimit = 24;

  /// 焦点图最多条目数。
  static const int _bannerLimit = 5;

  /// 加载首页。
  ///
  /// [sectionLimit] 可调低以加快首屏（例如弱网下只取前 N 条）。
  Future<HomeFeed> load({int? maxSections}) async {
    final candidates = await _candidateSources();
    if (candidates.isEmpty) return HomeFeed.none();

    final primary = candidates.first;
    final warnings = <String>[];
    final loaded = <HomeSection>[];

    final definitions = maxSections == null
        ? sections
        : sections.take(maxSections).toList(growable: false);

    // 各分区并发加载（内部分区内串行降级）。
    final results = await Future.wait(
      definitions.map((definition) => _loadSection(definition, candidates)),
    );

    for (var i = 0; i < definitions.length; i++) {
      final section = results[i];
      if (section == null) {
        warnings.add('「${definitions[i].title}」分区暂无数据');
        continue;
      }
      loaded.add(section);
    }

    if (loaded.isEmpty) {
      warnings.add('主源 ${primary.name} 未返回任何分类数据');
    }

    return HomeFeed(
      banners: _pickBanners(loaded),
      sections: List<HomeSection>.unmodifiable(loaded),
      sourceKey: loaded.isNotEmpty ? loaded.first.sourceKey : primary.key,
      sourceName: loaded.isNotEmpty ? loaded.first.sourceName : primary.name,
      loadedAt: DateTime.now(),
      warnings: List<String>.unmodifiable(warnings),
    );
  }

  // ── 内部 ────────────────────────────────────────────────

  /// 候选源：启用 + 类型受支持 + 声明了分类端点，按优先级升序。
  Future<List<SourceConfig>> _candidateSources() async {
    final sources = await _sourceRepository.loadSources();
    final candidates = sources
        .where(
          (s) =>
              s.enabled &&
              s.kind.isClientSupported &&
              s.effectiveEndpoints.category != null &&
              (s.effectiveEndpoints.category ?? '').trim().isNotEmpty,
        )
        .toList()
      ..sort((a, b) => a.priority.compareTo(b.priority));
    return candidates;
  }

  /// 加载单个分区，失败时按优先级降级到下一个候选源。
  Future<HomeSection?> _loadSection(
    HomeSectionDefinition definition,
    List<SourceConfig> candidates,
  ) async {
    for (final source in candidates) {
      try {
        final movies = await _movieRepository.browseCategory(
          sourceKey: source.key,
          typeId: definition.typeId,
        );
        if (movies.isEmpty) continue;

        return HomeSection(
          id: definition.id,
          title: definition.title,
          subtitle: definition.subtitle,
          sourceKey: source.key,
          sourceName: source.name,
          typeId: definition.typeId,
          movies: movies.take(_sectionLimit).toList(growable: false),
        );
      } on Failure {
        // 该源该分区失败 → 尝试下一个候选源
        continue;
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  /// 挑选焦点图：优先取有横版剧照的条目，不足则用竖版海报补齐。
  List<Movie> _pickBanners(List<HomeSection> sections) {
    final all = <Movie>[];
    for (final section in sections) {
      all.addAll(section.movies);
    }
    if (all.isEmpty) return const <Movie>[];

    // 去重（同一部片可能在多个分区出现）
    final seen = <String>{};
    final unique = <Movie>[];
    for (final movie in all) {
      if (seen.add(movie.id)) unique.add(movie);
    }

    final withBackdrop = unique
        .where((m) => (m.backdrop ?? '').trim().isNotEmpty)
        .toList(growable: false);

    final pool = withBackdrop.isNotEmpty ? withBackdrop : unique;
    return pool.take(_bannerLimit).toList(growable: false);
  }
}
