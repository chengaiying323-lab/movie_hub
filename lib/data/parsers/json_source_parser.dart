import '../../core/error/exceptions.dart';
import '../../core/utils/html_utils.dart';
import '../../core/utils/id_generator.dart';
import '../../core/utils/json_path.dart';
import '../../core/utils/title_normalizer.dart';
import '../../domain/entities/episode.dart';
import '../../domain/entities/movie.dart';
import '../../domain/entities/play_source.dart';
import '../../domain/entities/source_config.dart';
import 'source_parser.dart';

/// JSON 系数据源的公共解析基类。
///
/// 苹果CMS、TVBox JSON API 乃至自建接口，其响应结构虽有差异，
/// 但「条目定位 → 字段映射 → 播放串拆解」三个环节是共通的。
/// 本基类把这部分抽象出来，子类只需实现 [extractItems] 定位条目数组。
abstract class JsonSourceParser extends SourceParser {
  const JsonSourceParser();

  /// 在响应体中定位影视条目数组。
  ///
  /// 不同生态的响应外层结构不同，由子类负责归一：
  /// - 苹果CMS：`{"code":1,"list":[...]}` → 取 `list`
  /// - TVBox：`{"list":[...]}` 或 `{"data":{"list":[...]}}`
  List<Map<String, Object?>> extractItems(Object? payload, SourceConfig config);

  @override
  List<Movie> parseList(
    Object? payload,
    SourceConfig config, {
    bool withPlaylist = false,
  }) {
    final items = extractItems(payload, config);
    if (items.isEmpty) return const <Movie>[];

    final movies = <Movie>[];
    for (final raw in items) {
      final movie = _mapMovie(raw, config, withPlaylist: withPlaylist);
      if (movie != null && movie.title.isNotEmpty) movies.add(movie);
    }
    return movies;
  }

  @override
  Movie? parseDetail(
    Object? payload,
    SourceConfig config, {
    String? fallbackId,
  }) {
    final items = extractItems(payload, config);
    if (items.isEmpty) return null;

    // 详情接口正常只返回一条；若多条则优先匹配 fallbackId。
    Map<String, Object?> target = items.first;
    if (fallbackId != null && items.length > 1) {
      for (final item in items) {
        final id = JsonPath.str(item, config.fields.id);
        if (id == fallbackId) {
          target = item;
          break;
        }
      }
    }

    return _mapMovie(target, config, withPlaylist: true, fallbackId: fallbackId);
  }

  // ── 核心映射 ────────────────────────────────────────────

  /// 原始条目 → [Movie]。
  ///
  /// 全过程由 [SourceConfig.fields] 驱动，无任何站点特化分支。
  Movie? _mapMovie(
    Map<String, Object?> raw,
    SourceConfig config, {
    required bool withPlaylist,
    String? fallbackId,
  }) {
    try {
      final fields = config.fields;

      final vodId = JsonPath.str(raw, fields.id, fallback: fallbackId ?? '');
      final title = JsonPath.str(raw, fields.name).trim();
      if (title.isEmpty) return null;

      final movieId = IdGenerator.movieId(config.key, vodId);

      final rawYear = JsonPath.strOrNull(raw, fields.year);
      final year = JsonPath.intOrNull(raw, fields.year) ??
          (rawYear == null ? null : TitleNormalizer.extractYear(rawYear));

      // 分类：源站可能返回 `动作,科幻` / `动作|科幻` / `动作 科幻`
      final rawCategories = JsonPath.strOrNull(raw, fields.categories);
      final categories = rawCategories == null
          ? _fallbackCategories(JsonPath.strOrNull(raw, fields.typeName))
          : JsonPath.splitList(rawCategories.replaceAll(RegExp(r'[|/]'), ','));

      return Movie(
        id: movieId,
        vodId: vodId,
        sourceKey: config.key,
        sourceName: config.name,
        title: title,
        subTitle: JsonPath.strOrNull(raw, fields.subTitle),
        poster: HtmlUtils.resolveUrl(
              JsonPath.strOrNull(raw, fields.poster),
              config.api,
            ) ??
            '',
        backdrop: HtmlUtils.resolveUrl(
          JsonPath.strOrNull(raw, fields.backdrop),
          config.api,
        ),
        typeId: JsonPath.strOrNull(raw, fields.typeId),
        typeName: JsonPath.strOrNull(raw, fields.typeName),
        categories: categories,
        year: year,
        area: _normalizeRegion(JsonPath.strOrNull(raw, fields.area)),
        language: JsonPath.strOrNull(raw, fields.language),
        remarks: JsonPath.strOrNull(raw, fields.remarks),
        actors: JsonPath.splitList(
          JsonPath.strOrNull(raw, fields.actors)?.replaceAll(RegExp(r'[|，、/]'), ','),
        ),
        directors: JsonPath.splitList(
          JsonPath.strOrNull(raw, fields.directors)?.replaceAll(RegExp(r'[|，、/]'), ','),
        ),
        description: _normalizeDescription(
          JsonPath.strOrNull(raw, fields.description),
        ),
        score: _normalizeScore(JsonPath.doubleOrNull(raw, fields.score)),
        updatedAt: _parseTime(JsonPath.strOrNull(raw, fields.updatedAt)),
        detailUrl: HtmlUtils.resolveUrl(
          JsonPath.strOrNull(raw, fields.detailUrl),
          config.api,
        ),
        sources: withPlaylist ? _parsePlaylist(raw, config, movieId) : const <PlaySource>[],
        raw: raw,
      );
    } on SourceParseException {
      rethrow;
    } catch (error) {
      throw SourceParseException(
        '字段映射失败：$error',
        sourceKey: config.key,
        cause: error,
      );
    }
  }

  // ── 播放串拆解（协议核心算法） ────────────────────────────

  /// 拆解 `vod_play_from` / `vod_play_url` 双层结构。
  ///
  /// ```text
  /// play_from = "线路A$$$线路B"
  /// play_url  = "第1集$u1#第2集$u2$$$第01话$vA#第02话$vB"
  ///                          ↑ 线路分隔              ↑ 剧集分隔
  /// ```
  ///
  /// 容错点：
  /// 1. 两条串线路数不一致（源站数据残缺）→ 以 play_url 为准，缺失名回退 `线路N`；
  /// 2. 分隔符被重复书写（`$$$$`）→ 归一化后再切；
  /// 3. 分组为空（`$$$` 连续出现）→ 跳过，不产生空线路。
  List<PlaySource> _parsePlaylist(
    Map<String, Object?> raw,
    SourceConfig config,
    String movieId,
  ) {
    final rule = config.playlistRule;
    final playFrom = JsonPath.str(raw, config.fields.playFrom);
    final playUrl = JsonPath.str(raw, config.fields.playUrl);

    if (playUrl.trim().isEmpty) return const <PlaySource>[];

    final normalizedUrl = _normalizeSeparator(playUrl, rule.sourceSeparator);
    final normalizedFrom = _normalizeSeparator(playFrom, rule.sourceSeparator);

    final urlGroups = normalizedUrl.split(rule.sourceSeparator);
    final flags = normalizedFrom.isEmpty
        ? const <String>[]
        : normalizedFrom.split(rule.sourceSeparator);

    final result = <PlaySource>[];
    for (var i = 0; i < urlGroups.length; i++) {
      final group = urlGroups[i];
      if (group.trim().isEmpty) continue;

      final flag = i < flags.length && flags[i].trim().isNotEmpty
          ? flags[i].trim()
          : 'p${i + 1}';

      final episodes = _parseEpisodes(group, rule, i);
      if (episodes.isEmpty) continue;

      result.add(
        PlaySource(
          id: IdGenerator.playSourceId(movieId, flag),
          name: rule.displayNameOf(flag),
          flag: flag,
          episodes: episodes,
          fromSourceKey: config.key,
          fromSourceName: config.name,
          isDefault: result.isEmpty,
        ),
      );
    }
    return result;
  }

  /// 拆解单条线路内的选集串。
  List<Episode> _parseEpisodes(String group, PlaylistRule rule, int groupIndex) {
    final segments = group.split(rule.episodeSeparator);
    final episodes = <Episode>[];

    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i].trim();
      if (segment.isEmpty) continue;

      final separatorIndex = segment.indexOf(rule.nameSeparator);
      String name;
      String url;

      if (separatorIndex <= 0) {
        // 无「名称$地址」分界：整段即地址，名称按序号生成。
        name = '';
        url = segment;
      } else {
        name = segment.substring(0, separatorIndex).trim();
        url = segment.substring(separatorIndex + rule.nameSeparator.length).trim();
      }

      if (url.isEmpty || url == '#') continue;

      episodes.add(
        Episode(
          index: i,
          name: name.isEmpty ? '第${i + 1}集' : name,
          url: url,
          flag: _detectEpisodeFlag(name),
        ),
      );
    }

    if (rule.reverseEpisodes) {
      final reversed = episodes.reversed.toList(growable: false);
      return <Episode>[
        for (var i = 0; i < reversed.length; i++)
          reversed[i].copyWith(index: i),
      ];
    }

    // 重排 index，保证连续（源站偶有断号）。
    return <Episode>[
      for (var i = 0; i < episodes.length; i++) episodes[i].copyWith(index: i),
    ];
  }

  /// 归一化被重复书写的分隔符，如 `$$$$` → `$$$`。
  ///
  /// 只匹配「长度 ≥ 分隔符长度」的连续字符段，因此不会误伤单字符的
  /// 剧集名分隔符 `$`（`第1集$http://...`）。
  static String _normalizeSeparator(String input, String separator) {
    if (separator.length < 2 || input.isEmpty) return input;
    final char = RegExp.escape(separator[0]);
    final runPattern = RegExp('$char{${separator.length},}');
    return input.replaceAllMapped(runPattern, (_) => separator);
  }

  static String? _detectEpisodeFlag(String name) {
    if (name.contains('预告')) return 'preview';
    if (name.contains('VIP') || name.contains('vip')) return 'vip';
    return null;
  }

  static String? _normalizeDescription(String? raw) {
    if (raw == null) return null;
    final text = HtmlUtils.stripHtml(raw);
    return text.isEmpty ? null : text;
  }

  /// 评分归一化：部分源站返回 10 分制，部分返回百分制或 5 分制。
  static double? _normalizeScore(double? raw) {
    if (raw == null || raw <= 0) return null;
    if (raw > 10) return (raw / 10).clamp(0, 10);
    return raw;
  }

  /// 地区归一化：`大陆` → `中国大陆`，`香港` → `中国香港`。
  static String? _normalizeRegion(String? raw) {
    if (raw == null) return null;
    final value = raw.trim();
    if (value.isEmpty) return null;
    const map = <String, String>{
      '大陆': '中国大陆',
      '内地': '中国大陆',
      '香港': '中国香港',
      '台湾': '中国台湾',
      '澳门': '中国澳门',
    };
    return map[value] ?? value;
  }

  static DateTime? _parseTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final direct = DateTime.tryParse(raw);
    if (direct != null) return direct;
    // 形如 2024-05-01 12:00:00 / 20240501
    final compact = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(raw.trim());
    if (compact != null) {
      return DateTime(
        int.parse(compact.group(1)!),
        int.parse(compact.group(2)!),
        int.parse(compact.group(3)!),
      );
    }
    return null;
  }

  static List<String> _fallbackCategories(String? typeName) {
    if (typeName == null || typeName.trim().isEmpty) return const <String>[];
    return JsonPath.splitList(typeName.replaceAll(RegExp(r'[|/、]'), ','));
  }
}
