import '../../core/utils/id_generator.dart';
import '../../core/utils/json_path.dart';
import '../../domain/entities/episode.dart';
import '../../domain/entities/movie.dart';
import '../../domain/entities/play_source.dart';
import '../../domain/entities/source_config.dart';
import 'json_source_parser.dart';

/// 通用 JSON API 解析器（TVBox `type=0/1` 站点、自建接口）。
///
/// 与 [MaccmsParser] 的差异
/// ------------------------------------------------------------------
/// 1. 响应外层结构更自由：可能直接是数组，也可能是 `{data:[...]}`；
/// 2. 详情可能返回 `{list:[{...}]}`（TVBox 惯例）而非 `{data:{...}}`；
/// 3. **选集结构可能不是播放串**，而是结构化数组：
///    ```json
///    { "episodes": [ {"name": "第1集", "url": "https://..."} ] }
///    ```
///    本解析器优先识别结构化数组，识别失败再回退到播放串拆解。
class TvboxJsonParser extends JsonSourceParser {
  const TvboxJsonParser();

  @override
  SourceKind get kind => SourceKind.tvboxJson;

  /// 结构化选集字段的候选路径（协议未声明时的通用探测）。
  static const List<String> _structuredEpisodePaths = <String>[
    'episodes',
    'urls',
    'playlist',
    'play_list',
    'video_list',
  ];

  @override
  List<Map<String, Object?>> extractItems(Object? payload, SourceConfig config) {
    final declared = JsonPath.mapList(payload, config.fields.list);
    if (declared.isNotEmpty) return declared;

    for (final path in const <String>[
      'list',
      'data.list',
      'data',
      'result.list',
      'result',
      'items',
    ]) {
      final fallback = JsonPath.mapList(payload, path);
      if (fallback.isNotEmpty) return fallback;
    }

    if (payload is List) {
      return payload
          .whereType<Map>()
          .map((e) => e.cast<String, Object?>())
          .toList(growable: false);
    }
    return const <Map<String, Object?>>[];
  }

  @override
  Movie? parseDetail(
    Object? payload,
    SourceConfig config, {
    String? fallbackId,
  }) {
    final movie = super.parseDetail(payload, config, fallbackId: fallbackId);
    if (movie == null) return null;
    if (movie.sources.isNotEmpty) return movie;

    // 播放串缺失 → 尝试结构化选集数组
    final items = extractItems(payload, config);
    if (items.isEmpty) return movie;

    final structured = _parseStructuredEpisodes(
      items.first,
      config,
      IdGenerator.movieId(config.key, movie.vodId),
    );
    if (structured.isEmpty) return movie;
    return movie.copyWith(sources: structured);
  }

  /// 解析 `episodes: [{name, url}]` 形态。
  ///
  /// 兼容三种命名：`name`/`title`、`url`/`play_url`/`link`。
  List<PlaySource> _parseStructuredEpisodes(
    Map<String, Object?> raw,
    SourceConfig config,
    String movieId,
  ) {
    Object? container;
    for (final path in _structuredEpisodePaths) {
      final value = JsonPath.read(raw, path);
      if (value is List && value.isNotEmpty) {
        container = value;
        break;
      }
    }
    if (container is! List) return const <PlaySource>[];

    // 允许容器是「线路数组」：[[ep...], [ep...]] 或 [{flag, episodes: [...]}]
    final groups = <String, List<Episode>>{};

    for (var i = 0; i < container.length; i++) {
      final element = container[i];

      if (element is Map) {
        final map = element.cast<String, Object?>();
        final nested = JsonPath.read(map, 'episodes||urls||list');
        final flag = JsonPath.str(map, 'flag||name||title', fallback: 'p${i + 1}');

        if (nested is List && nested.isNotEmpty) {
          groups[flag] = _toEpisodes(nested);
          continue;
        }
        // 单集对象
        final single = _toEpisode(map, 0);
        if (single != null) {
          groups.putIfAbsent('p1', () => <Episode>[]).add(single);
        }
        continue;
      }

      if (element is String && element.trim().isNotEmpty) {
        groups.putIfAbsent('p1', () => <Episode>[]).add(
              Episode(index: i, name: '第${i + 1}集', url: element.trim()),
            );
      }
    }

    final result = <PlaySource>[];
    final rule = config.playlistRule;
    groups.forEach((flag, episodes) {
      if (episodes.isEmpty) return;
      result.add(
        PlaySource(
          id: IdGenerator.playSourceId(movieId, flag),
          name: rule.displayNameOf(flag),
          flag: flag,
          episodes: <Episode>[
            for (var i = 0; i < episodes.length; i++) episodes[i].copyWith(index: i),
          ],
          fromSourceKey: config.key,
          fromSourceName: config.name,
          isDefault: result.isEmpty,
        ),
      );
    });
    return result;
  }

  List<Episode> _toEpisodes(List<dynamic> raw) {
    final episodes = <Episode>[];
    for (var i = 0; i < raw.length; i++) {
      final element = raw[i];
      if (element is Map) {
        final episode = _toEpisode(element.cast<String, Object?>(), i);
        if (episode != null) episodes.add(episode);
      } else if (element is String && element.trim().isNotEmpty) {
        episodes.add(Episode(index: i, name: '第${i + 1}集', url: element.trim()));
      }
    }
    return episodes;
  }

  Episode? _toEpisode(Map<String, Object?> raw, int fallbackIndex) {
    final url = JsonPath.strOrNull(raw, 'url||play_url||link||src');
    if (url == null) return null;
    return Episode(
      index: fallbackIndex,
      name: JsonPath.str(raw, 'name||title||label',
          fallback: '第${fallbackIndex + 1}集'),
      url: url,
    );
  }
}
