import 'package:meta/meta.dart';

import '../../core/utils/json_path.dart';
import 'play_source.dart';

/// 标准影视元数据模型（MovieModel）。
///
/// 设计原则
/// ------------------------------------------------------------------
/// **1. 与源站的原始字段彻底解耦。**
/// 本模型不使用 `vod_id` / `vod_name` / `vod_pic` 这类苹果CMS原生字段名，
/// 而是采用语义化命名；原始字段 → 本模型的映射由 `FieldMapping` 配置驱动。
/// 这样切换到 TVBox JSON 源或自建 API 源时，Model 层零改动。
///
/// **2. 冗余字段规范化。**
/// `cate` / `area` / `language` 等在各源站格式混乱（逗号/斜杠/空格分隔），
/// 统一在解析层归一为 `List<String>`。
///
/// **3. 保留 `raw` 逃生舱。**
/// 部分源站有私有扩展字段（评分榜、弹幕 ID 等），聚合层无法预先枚举，
/// 因此保留原始 Map 供上层按需取用（`raw['xxx']`），但不参与相等性判定。
@immutable
class Movie {
  const Movie({
    required this.id,
    required this.vodId,
    required this.sourceKey,
    required this.sourceName,
    required this.title,
    this.subTitle,
    this.poster = '',
    this.backdrop,
    this.typeId,
    this.typeName,
    this.categories = const <String>[],
    this.year,
    this.area,
    this.language,
    this.remarks,
    this.actors = const <String>[],
    this.directors = const <String>[],
    this.description,
    this.score,
    this.duration,
    this.updatedAt,
    this.detailUrl,
    this.sources = const <PlaySource>[],
    this.raw,
  });

  /// ── 标识 ────────────────────────────────────────────────
  /// 全局唯一 ID，格式 `{sourceKey}:{vodId}`。
  final String id;

  /// 源站内的原始资源 ID。
  final String vodId;

  /// 所属数据源标识。
  final String sourceKey;

  /// 所属数据源展示名（用于「来源」角标）。
  final String sourceName;

  /// ── 基础元数据 ──────────────────────────────────────────
  final String title;
  final String? subTitle;

  /// 竖版封面海报 URL。
  final String poster;

  /// 横版剧照 / 背景图 URL（详情页顶部使用）。
  final String? backdrop;

  final String? typeId;
  final String? typeName;

  /// 归一化后的分类标签（多值），如 `['动作', '科幻']`。
  final List<String> categories;

  /// 上映年份。
  final int? year;

  final String? area;
  final String? language;

  /// 更新备注，如「更新至 24 集」「HD 国语」。
  final String? remarks;

  final List<String> actors;
  final List<String> directors;

  /// 剧情简介（HTML 已剥离或原样保留，由 UI 层决定是否清洗）。
  final String? description;

  /// 评分 0.0 ~ 10.0。
  final double? score;

  final String? duration;

  /// 源站最后更新时间。
  final DateTime? updatedAt;

  /// 详情页地址（部分源站列表接口不返回完整信息，需二次请求）。
  final String? detailUrl;

  /// ── 播放数据 ────────────────────────────────────────────
  /// 播放线路列表。列表接口可能为空，详情接口才会填充。
  final List<PlaySource> sources;

  /// 未映射的原始字段，供上层扩展使用。
  final Map<String, dynamic>? raw;

  // ── 派生属性 ────────────────────────────────────────────

  bool get hasPlaySources => sources.any((s) => s.hasPlayable);

  int get totalEpisodes =>
      sources.fold<int>(0, (sum, s) => sum + s.episodeCount);

  /// 首选线路：按线路质量分排序取最优。
  PlaySource? get preferredSource {
    if (sources.isEmpty) return null;
    final sorted = [...sources]..sort(
        (a, b) => b.qualityScore.compareTo(a.qualityScore),
      );
    return sorted.first;
  }

  /// 展示用副标题：`2024 · 动作 / 科幻 · 更新至 24 集`
  String get displaySubtitle {
    final parts = <String>[
      if (year != null) '$year',
      if (categories.isNotEmpty) categories.take(2).join(' / '),
      if (remarks != null && remarks!.isNotEmpty) remarks!,
    ];
    return parts.join(' · ');
  }

  /// 是否与关键词相关（用于过滤搜索接口的模糊噪声）。
  bool matchesKeyword(String keyword) {
    final k = keyword.trim().toLowerCase();
    if (k.isEmpty) return true;
    return title.toLowerCase().contains(k) ||
        (subTitle?.toLowerCase().contains(k) ?? false) ||
        actors.any((a) => a.toLowerCase().contains(k)) ||
        directors.any((d) => d.toLowerCase().contains(k));
  }

  Movie copyWith({
    String? id,
    String? vodId,
    String? sourceKey,
    String? sourceName,
    String? title,
    String? subTitle,
    String? poster,
    String? backdrop,
    String? typeId,
    String? typeName,
    List<String>? categories,
    int? year,
    String? area,
    String? language,
    String? remarks,
    List<String>? actors,
    List<String>? directors,
    String? description,
    double? score,
    String? duration,
    DateTime? updatedAt,
    String? detailUrl,
    List<PlaySource>? sources,
    Map<String, dynamic>? raw,
  }) =>
      Movie(
        id: id ?? this.id,
        vodId: vodId ?? this.vodId,
        sourceKey: sourceKey ?? this.sourceKey,
        sourceName: sourceName ?? this.sourceName,
        title: title ?? this.title,
        subTitle: subTitle ?? this.subTitle,
        poster: poster ?? this.poster,
        backdrop: backdrop ?? this.backdrop,
        typeId: typeId ?? this.typeId,
        typeName: typeName ?? this.typeName,
        categories: categories ?? this.categories,
        year: year ?? this.year,
        area: area ?? this.area,
        language: language ?? this.language,
        remarks: remarks ?? this.remarks,
        actors: actors ?? this.actors,
        directors: directors ?? this.directors,
        description: description ?? this.description,
        score: score ?? this.score,
        duration: duration ?? this.duration,
        updatedAt: updatedAt ?? this.updatedAt,
        detailUrl: detailUrl ?? this.detailUrl,
        sources: sources ?? this.sources,
        raw: raw ?? this.raw,
      );

  // ── 序列化（本地缓存 / 跨 isolate 传递） ──────────────────

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'vodId': vodId,
        'sourceKey': sourceKey,
        'sourceName': sourceName,
        'title': title,
        'subTitle': subTitle,
        'poster': poster,
        'backdrop': backdrop,
        'typeId': typeId,
        'typeName': typeName,
        'categories': categories,
        'year': year,
        'area': area,
        'language': language,
        'remarks': remarks,
        'actors': actors,
        'directors': directors,
        'description': description,
        'score': score,
        'duration': duration,
        'updatedAt': updatedAt?.toIso8601String(),
        'detailUrl': detailUrl,
        'sources': sources.map((s) => s.toJson()).toList(),
      };

  factory Movie.fromJson(Map<String, dynamic> json) => Movie(
        id: json['id'] as String? ?? '',
        vodId: json['vodId'] as String? ?? '',
        sourceKey: json['sourceKey'] as String? ?? '',
        sourceName: json['sourceName'] as String? ?? '',
        title: json['title'] as String? ?? '',
        subTitle: json['subTitle'] as String?,
        poster: json['poster'] as String? ?? '',
        backdrop: json['backdrop'] as String?,
        typeId: json['typeId'] as String?,
        typeName: json['typeName'] as String?,
        categories: _parseStringList(json['categories']),
        year: (json['year'] as num?)?.toInt(),
        area: json['area'] as String?,
        language: json['language'] as String?,
        remarks: json['remarks'] as String?,
        actors: (json['actors'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => '$e')
            .toList(growable: false),
        directors: (json['directors'] as List<dynamic>? ?? const <dynamic>[])
            .map((e) => '$e')
            .toList(growable: false),
        description: json['description'] as String?,
        score: (json['score'] as num?)?.toDouble(),
        duration: json['duration'] as String?,
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
        detailUrl: json['detailUrl'] as String?,
        sources: (json['sources'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(PlaySource.fromJson)
            .toList(growable: false),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Movie && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'Movie($id, $title, ${sources.length} 线路 / $totalEpisodes 集)';

  /// 兼容 `List` 与 `"动作,科幻"` 两种序列化形态。
  static List<String> _parseStringList(Object? value) {
    if (value is List) {
      return value
          .map((e) => '$e'.trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
    }
    if (value is String) {
      return JsonPath.splitList(value);
    }
    return const <String>[];
  }
}
