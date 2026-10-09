import 'package:meta/meta.dart';

import 'episode.dart';

/// 播放线路（线路/源）实体。
///
/// 对应苹果CMS `vod_play_from` / `vod_play_url` 拆解出的一个分组。
/// 同一部影片通常有 2~8 条线路（如「闪电线路」「量子线路」「m3u8」），
/// 线路之间画质、稳定性、更新进度各不相同，必须保留全部并允许用户切换。
@immutable
class PlaySource {
  const PlaySource({
    required this.id,
    required this.name,
    required this.flag,
    required this.episodes,
    this.fromSourceKey,
    this.fromSourceName,
    this.isDefault = false,
  });

  /// 线路唯一 ID：`{movieId}#{flag}`。
  final String id;

  /// 展示名（对 flag 的人类可读化结果）。
  final String name;

  /// 源站原始线路标志，如 `dytt`、`m3u8`、`qiyi`。
  final String flag;

  /// 该线路下的完整选集列表。
  final List<Episode> episodes;

  /// 该线路来自哪个数据源（跨源聚合后用于溯源）。
  final String? fromSourceKey;
  final String? fromSourceName;

  /// 是否被聚合层标记为默认首选线路。
  final bool isDefault;

  int get episodeCount => episodes.length;

  /// 是否有任意一集可直接播放。
  bool get hasPlayable => episodes.any((e) => e.isPlayable);

  Episode? episodeAt(int index) {
    if (index < 0 || index >= episodes.length) return null;
    return episodes[index];
  }

  /// 按 [Episode.index]（集序号）取集，越界时回退到第一集。
  ///
  /// 与 [episodeAt] 的区别很重要：后者是**列表下标**，前者是**集序号**。
  /// 观看记录里存的、UI 上展示的、聚合层对齐的统统是集序号；
  /// 而集序号与下标并不总是相等（源站可能缺集、可能倒序）。
  /// 续播定位必须按集序号找，否则会出现"记录说第 8 集，打开却是列表第 8 项"。
  Episode? episodeByIndex(int index) {
    for (final episode in episodes) {
      if (episode.index == index) return episode;
    }
    return episodes.isEmpty ? null : episodes.first;
  }

  /// 首集播放地址，用于「立即播放」。
  String? get firstPlayUrl {
    for (final e in episodes) {
      if (e.isPlayable) return e.url;
    }
    return null;
  }

  /// 线路质量评分：聚合层据此挑选首选线路。
  ///
  /// 评分维度：可播放集数（权重最高）、直链比例、名称是否含高清标识。
  double get qualityScore {
    if (episodes.isEmpty) return 0;
    final playable = episodes.where((e) => e.isPlayable).toList();
    if (playable.isEmpty) return 0;
    final directRatio =
        playable.where((e) => e.isDirectMedia).length / playable.length;
    final nameBonus = RegExp(r'高清|蓝光|hdr|4k', caseSensitive: false)
            .hasMatch(name)
        ? 1.15
        : 1.0;
    return playable.length * (0.6 + 0.4 * directRatio) * nameBonus;
  }

  PlaySource copyWith({
    String? id,
    String? name,
    String? flag,
    List<Episode>? episodes,
    String? fromSourceKey,
    String? fromSourceName,
    bool? isDefault,
  }) =>
      PlaySource(
        id: id ?? this.id,
        name: name ?? this.name,
        flag: flag ?? this.flag,
        episodes: episodes ?? this.episodes,
        fromSourceKey: fromSourceKey ?? this.fromSourceKey,
        fromSourceName: fromSourceName ?? this.fromSourceName,
        isDefault: isDefault ?? this.isDefault,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'flag': flag,
        'episodes': episodes.map((e) => e.toJson()).toList(),
        if (fromSourceKey != null) 'fromSourceKey': fromSourceKey,
        if (fromSourceName != null) 'fromSourceName': fromSourceName,
        'isDefault': isDefault,
      };

  factory PlaySource.fromJson(Map<String, dynamic> json) => PlaySource(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        flag: json['flag'] as String? ?? '',
        episodes: (json['episodes'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(Episode.fromJson)
            .toList(growable: false),
        fromSourceKey: json['fromSourceKey'] as String?,
        fromSourceName: json['fromSourceName'] as String?,
        isDefault: json['isDefault'] as bool? ?? false,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is PlaySource && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'PlaySource($name, ${episodes.length} 集, score=${qualityScore.toStringAsFixed(1)})';
}
