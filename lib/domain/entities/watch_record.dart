import 'package:meta/meta.dart';

import '../../core/constants/app_constants.dart';
import 'movie.dart';

/// 观影状态。
///
/// 三态即资料库的三个分栏，也是本模块唯一的状态机：
/// ```
///            ┌──────────────┐
///            │  wantToWatch │ 想看（用户手动标记，尚无播放行为）
///            └──────┬───────┘
///     开始播放 │            │ 用户手动标记
///            ▼            ▼
///            ┌──────────────┐
///            │   watching   │ 正在看（有播放进度，未达完成阈值）
///            └──────┬───────┘
///  进度 ≥ 90% │            │ 用户手动标记
///            ▼            ▼
///            ┌──────────────┐
///            │   watched    │ 已看
///            └──────┬───────┘
///    重新播放 │
///            └──────────► watching（重看视为再次进入正在看）
/// ```
///
/// 注意：`watched` **不是终态**——用户重看时应当回到 `watching`，
/// 否则「继续观看」会在重看过程中永远消失。
enum WatchStatus {
  wantToWatch('want_to_watch', '想看'),
  watching('watching', '正在看'),
  watched('watched', '已看');

  const WatchStatus(this.storageKey, this.label);

  /// 持久化用字符串。
  ///
  /// 刻意**不使用 `enum.index`**：一旦后续在中间插入新枚举值，
  /// 已落盘的旧数据会被错误映射到别的状态。
  final String storageKey;

  /// 面向用户的短标签。
  final String label;

  /// 资料库分栏顺序：正在看 → 想看 → 已看。
  static const List<WatchStatus> tabOrder = <WatchStatus>[
    WatchStatus.watching,
    WatchStatus.wantToWatch,
    WatchStatus.watched,
  ];

  bool get isWatching => this == WatchStatus.watching;

  bool get isWatched => this == WatchStatus.watched;

  bool get isWantToWatch => this == WatchStatus.wantToWatch;

  /// 是否计入侧边栏「追剧」角标（已看不计入，避免数字只增不减）。
  bool get isActive => this == WatchStatus.watching || this == WatchStatus.wantToWatch;

  /// 反序列化；无法识别时回落到 [WatchStatus.wantToWatch]。
  static WatchStatus fromStorage(Object? value) {
    final key = '$value';
    for (final status in WatchStatus.values) {
      if (status.storageKey == key) return status;
    }
    return WatchStatus.wantToWatch;
  }
}

/// 观影记录（WatchRecord）。
///
/// 设计要点
/// ------------------------------------------------------------------
/// **1. 一条记录承载三种状态，而非"进度"与"收藏"两张表。**
/// 「想看」与「正在看」在用户心智里是同一份清单的不同阶段；
/// 拆成两张表会导致同一影片出现两条互不同步的数据。
///
/// **2. 复合唯一键 `{sourceKey}:{vodId}`。**
/// 同一部影片在不同源站的线路地址不通用（换源后需重新定位集数），
/// 因此以"源 + 源站资源 ID"为唯一键，而不是影片标题。
/// [id] 即该复合键，作为 Hive Box 的键实现 O(1) 命中。
///
/// **3. 进度字段可为零。**
/// 「想看」条目没有任何播放行为（[lastPositionMs] / [totalDurationMs] 为 0），
/// 因此所有百分比派生都做了除零保护。
@immutable
class WatchRecord {
  WatchRecord({
    required this.movieId,
    required this.sourceKey,
    required this.vodId,
    required this.title,
    required this.status,
    required this.updatedAt,
    this.sourceName = '',
    this.posterUrl = '',
    this.currentEpisodeTitle = '',
    this.currentEpisodeIndex = 0,
    this.lastPositionMs = 0,
    this.totalDurationMs = 0,
    this.playSourceFlag = '',
    this.playSourceName = '',
    this.episodeUrl = '',
    this.year,
    this.remarks,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? updatedAt;

  /// ── 标识 ────────────────────────────────────────────────

  /// 应用内影片全局 ID，格式 `{sourceKey}:{vodId}`（与 [Movie.id] 同源）。
  final String movieId;

  /// 所属数据源标识。
  final String sourceKey;

  /// 源站内的原始资源 ID。
  final String vodId;

  /// 复合主键 —— 即 Hive Box 的键。
  ///
  /// 由 [sourceKey] 与 [vodId] 派生而非独立存储：
  /// 三者若分别存储，一旦其中一处被改写就会出现"键与内容不一致"的脏数据。
  String get id => keyOf(sourceKey, vodId);

  /// 复合键构造器（供存储层 / 查询层复用，避免各处手拼字符串）。
  static String keyOf(String sourceKey, String vodId) => '$sourceKey:$vodId';

  /// ── 展示元数据 ──────────────────────────────────────────

  final String title;

  /// 来源展示名（卡片角标使用）。
  final String sourceName;

  /// 竖版封面海报 URL。
  ///
  /// 刻意**冗余存储**：只有本地存了海报地址，资料库才能在完全离线、
  /// 甚至数据源全部失效的情况下正常渲染。
  final String posterUrl;

  final int? year;
  final String? remarks;

  /// ── 播放位置 ────────────────────────────────────────────

  /// 上次播放到的选集名，如「第 3 集」。
  final String currentEpisodeTitle;

  /// 上次播放到的集序号（从 0 开始）。
  final int currentEpisodeIndex;

  /// 上次播放进度（毫秒）。
  final int lastPositionMs;

  /// 视频总时长（毫秒）。未知时为 0。
  final int totalDurationMs;

  /// 上次使用的播放线路（续播时据此定位到同一条线路）。
  final String playSourceFlag;
  final String playSourceName;

  /// 上次播放地址（供后续内嵌播放器直接起播）。
  final String episodeUrl;

  /// ── 状态与时间 ──────────────────────────────────────────

  final WatchStatus status;

  /// 最后更新时间。资料库排序与"最近观看"判定均以此为准。
  final DateTime updatedAt;

  /// 首次进入清单的时间（用于"想看多久了"这类展示，不参与排序）。
  final DateTime createdAt;

  // ── 派生属性 ────────────────────────────────────────────

  /// 播放进度百分比（0.0 ~ 1.0）。总时长未知时返回 0。
  double get percent {
    if (totalDurationMs <= 0) return 0;
    return (lastPositionMs / totalDurationMs).clamp(0.0, 1.0);
  }

  /// 百分比整数形式（用于展示）。
  int get percentInt => (percent * 100).round();

  /// 是否已有实际播放行为。
  bool get hasProgress => lastPositionMs > 0;

  /// 是否已达到"看完"阈值。
  ///
  /// 注意：这是**进度层面的判定**，与 [status] 无关
  /// —— 用户也可能手动把一部没看完的片子标成「已看」。
  bool get reachedWatchedThreshold => percent >= AppConstants.kWatchedThreshold;

  /// 集数展示文案：优先用源站给的选集名，缺失时按序号拼。
  String get episodeLabel {
    final name = currentEpisodeTitle.trim();
    if (name.isNotEmpty) return name;
    return '第 ${currentEpisodeIndex + 1} 集';
  }

  /// 资料库卡片上的一行进度描述，如 `第 3 集 · 已看 65%`。
  ///
  /// 总时长未知（如刚开播就退出）时退化为 `第 3 集`。
  String get progressLabel {
    final head = episodeLabel;
    if (totalDurationMs <= 0) return head;
    if (status.isWatched || reachedWatchedThreshold) return '$head · 已看完';
    return '$head · 已看 $percentInt%';
  }

  /// 是否值得在「继续观看」中展示。
  ///
  /// 排除两类噪声：
  /// 1. 刚点开就退出（进度低于 [AppConstants.kResumeMinPercent] 且仍是第 1 集）；
  /// 2. 已看完的条目（应当去「已看」分栏找）。
  bool get shouldResume {
    if (status.isWatched) return false;
    if (reachedWatchedThreshold) return false;
    if (currentEpisodeIndex > 0) return true;
    return percent > AppConstants.kResumeMinPercent;
  }

  /// 该记录是否指向「同一条线路的同一集」。
  ///
  /// 这是**续播判定的唯一依据**，被两处共享：
  /// * [WatchHistoryNotifier.beginSession] —— 决定新会话是否沿用旧进度；
  /// * 播放页 —— 决定把哪个位置写进 `PlaybackSource.startPositionMs`。
  ///
  /// 之所以要收敛成一个方法：这两处一旦判定不一致，就会出现
  /// "记录里是第 8 分钟，播放器却从第 3 分钟开始"这类极难排查的漂移。
  bool matchesEpisode({
    required String sourceFlag,
    required int episodeIndex,
  }) =>
      playSourceFlag == sourceFlag && currentEpisodeIndex == episodeIndex;

  /// 剩余时长（毫秒）；总时长未知时返回 0。
  int get remainingMs {
    if (totalDurationMs <= 0) return 0;
    final remain = totalDurationMs - lastPositionMs;    return remain > 0 ? remain : 0;
  }

  /// `18:30` / `1:02:45`
  static String formatDuration(int milliseconds) {
    if (milliseconds <= 0) return '00:00';
    final totalSeconds = milliseconds ~/ 1000;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
  }

  // ── 变换 ────────────────────────────────────────────────

  /// 从影片元数据构造一条「想看」记录（最常用入口）。
  factory WatchRecord.wantToWatch(Movie movie, {DateTime? now}) {
    final timestamp = now ?? DateTime.now();
    return WatchRecord(
      movieId: movie.id,
      sourceKey: movie.sourceKey,
      vodId: movie.vodId,
      sourceName: movie.sourceName,
      title: movie.title,
      posterUrl: movie.poster,
      year: movie.year,
      remarks: movie.remarks,
      status: WatchStatus.wantToWatch,
      updatedAt: timestamp,
      createdAt: timestamp,
    );
  }

  WatchRecord copyWith({
    String? movieId,
    String? sourceKey,
    String? vodId,
    String? title,
    String? sourceName,
    String? posterUrl,
    int? year,
    String? remarks,
    String? currentEpisodeTitle,
    int? currentEpisodeIndex,
    int? lastPositionMs,
    int? totalDurationMs,
    String? playSourceFlag,
    String? playSourceName,
    String? episodeUrl,
    WatchStatus? status,
    DateTime? updatedAt,
    DateTime? createdAt,
  }) =>
      WatchRecord(
        movieId: movieId ?? this.movieId,
        sourceKey: sourceKey ?? this.sourceKey,
        vodId: vodId ?? this.vodId,
        title: title ?? this.title,
        sourceName: sourceName ?? this.sourceName,
        posterUrl: posterUrl ?? this.posterUrl,
        year: year ?? this.year,
        remarks: remarks ?? this.remarks,
        currentEpisodeTitle: currentEpisodeTitle ?? this.currentEpisodeTitle,
        currentEpisodeIndex: currentEpisodeIndex ?? this.currentEpisodeIndex,
        lastPositionMs: lastPositionMs ?? this.lastPositionMs,
        totalDurationMs: totalDurationMs ?? this.totalDurationMs,
        playSourceFlag: playSourceFlag ?? this.playSourceFlag,
        playSourceName: playSourceName ?? this.playSourceName,
        episodeUrl: episodeUrl ?? this.episodeUrl,
        status: status ?? this.status,
        updatedAt: updatedAt ?? this.updatedAt,
        createdAt: createdAt ?? this.createdAt,
      );

  // ── 序列化 ──────────────────────────────────────────────

  /// 扁平化 Map。
  ///
  /// 同时服务于两处：
  /// 1. Hive 手写 TypeAdapter（读写该 Map）；
  /// 2. 旧版本 SharedPreferences JSON 数据的迁移。
  Map<String, dynamic> toMap() => <String, dynamic>{
        'movie_id': movieId,
        'source_key': sourceKey,
        'vod_id': vodId,
        'title': title,
        'source_name': sourceName,
        'poster_url': posterUrl,
        'year': year,
        'remarks': remarks,
        'episode_title': currentEpisodeTitle,
        'episode_index': currentEpisodeIndex,
        'position_ms': lastPositionMs,
        'duration_ms': totalDurationMs,
        'play_source_flag': playSourceFlag,
        'play_source_name': playSourceName,
        'episode_url': episodeUrl,
        'status': status.storageKey,
        'updated_at': updatedAt.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
      };

  factory WatchRecord.fromMap(Map<dynamic, dynamic> map) {
    // 兼容旧字段名（poster / episode_name / position / duration）
    final poster = _str(map['poster_url']) ?? _str(map['poster']) ?? '';
    final episodeTitle =
        _str(map['episode_title']) ?? _str(map['episode_name']) ?? '';
    final position = _int(map['position_ms']) ?? _int(map['position']) ?? 0;
    final duration = _int(map['duration_ms']) ?? _int(map['duration']) ?? 0;
    final updatedAt = _dateTime(map['updated_at']) ??
        DateTime.fromMillisecondsSinceEpoch(0);

    return WatchRecord(
      movieId: _str(map['movie_id']) ?? '',
      sourceKey: _str(map['source_key']) ?? '',
      vodId: _str(map['vod_id']) ?? '',
      title: _str(map['title']) ?? '',
      sourceName: _str(map['source_name']) ?? '',
      posterUrl: poster,
      year: _int(map['year']),
      remarks: _str(map['remarks']),
      currentEpisodeTitle: episodeTitle,
      currentEpisodeIndex: _int(map['episode_index']) ?? 0,
      lastPositionMs: position,
      totalDurationMs: duration,
      playSourceFlag: _str(map['play_source_flag']) ?? '',
      playSourceName: _str(map['play_source_name']) ?? '',
      episodeUrl: _str(map['episode_url']) ?? '',
      status: WatchStatus.fromStorage(map['status']),
      updatedAt: updatedAt,
      createdAt: _dateTime(map['created_at']) ?? updatedAt,
    );
  }

  static String? _str(Object? value) {
    if (value == null) return null;
    final text = '$value';
    return text.isEmpty ? null : text;
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static DateTime? _dateTime(Object? value) {
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  // ── 相等性 / 排序 ───────────────────────────────────────

  /// 「最近更新优先」比较器，供资料库与继续观看统一排序。
  static int byUpdatedAtDesc(WatchRecord a, WatchRecord b) =>
      b.updatedAt.compareTo(a.updatedAt);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WatchRecord &&
          other.sourceKey == sourceKey &&
          other.vodId == vodId;

  @override
  int get hashCode => Object.hash(sourceKey, vodId);

  @override
  String toString() =>
      'WatchRecord($id, $title, ${status.label}, ${status.isWatching || status.isWatched ? "${percentInt}%" : "-"})';
}

/// 观影清单聚合状态。
///
/// 一次性持有全量记录并预分组，避免三个 Tab 各自遍历全表。
/// 记录数上限 [AppConstants.kMaxWatchRecords]（500），分组开销可忽略。
@immutable
class WatchHistoryState {
  WatchHistoryState({List<WatchRecord> records = const <WatchRecord>[]})
      : records = List<WatchRecord>.unmodifiable(records);

  static final WatchHistoryState empty = WatchHistoryState();

  /// 全量记录，按 [WatchRecord.updatedAt] 倒序。
  final List<WatchRecord> records;

  /// ── 预分组（首次访问时计算一次） ──────────────────────

  late final List<WatchRecord> watching = _of(WatchStatus.watching);
  late final List<WatchRecord> wantToWatchList = _of(WatchStatus.wantToWatch);
  late final List<WatchRecord> watched = _of(WatchStatus.watched);

  /// 「继续观看」：正在看、且进度处于"值得续播"区间。
  late final List<WatchRecord> resumable = List<WatchRecord>.unmodifiable(
    watching.where((r) => r.shouldResume),
  );

  /// 便捷索引：`movieId` → 记录。
  late final Map<String, WatchRecord> _byMovieId = <String, WatchRecord>{
    for (final record in records) record.movieId: record,
  };

  List<WatchRecord> _of(WatchStatus status) => List<WatchRecord>.unmodifiable(
        records.where((r) => r.status == status),
      );

  /// 按状态取分栏列表。
  List<WatchRecord> of(WatchStatus status) {
    switch (status) {
      case WatchStatus.watching:
        return watching;
      case WatchStatus.wantToWatch:
        return wantToWatchList;
      case WatchStatus.watched:
        return watched;
    }
  }

  /// 侧边栏「追剧」角标数量（正在看 + 想看，不含已看）。
  int get activeCount => records.where((r) => r.status.isActive).length;

  int get total => records.length;

  bool get isEmpty => records.isEmpty;

  WatchRecord? find(String movieId) => _byMovieId[movieId];

  bool contains(String movieId) => _byMovieId.containsKey(movieId);

  WatchStatus? statusOf(String movieId) => _byMovieId[movieId]?.status;

  int countOf(WatchStatus status) => of(status).length;

  WatchHistoryState copyWith({List<WatchRecord>? records}) =>
      WatchHistoryState(records: records ?? this.records);
}
