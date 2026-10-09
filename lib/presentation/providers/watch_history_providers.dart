import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../domain/entities/episode.dart';
import '../../domain/entities/movie.dart';
import '../../domain/entities/play_source.dart';
import '../../domain/entities/watch_record.dart';
import '../../domain/repositories/watch_history_repository.dart';
import 'core_providers.dart';

/// ─────────────────────────────────────────────────────────────
/// 观影记录状态（想看 / 正在看 / 已看）
///
/// 一个 AsyncNotifier 承担三件事：
/// 1. **状态机**：手动标记与自动流转（播放→正在看，≥90%→已看）；
/// 2. **进度回写**：会话期间按 [AppConstants.kProgressFlushInterval]
///    周期落盘，暂停/切集/退出时立即补写；
/// 3. **离线查询**：所有 Tab、续播判定都从内存快照读取，不触发 IO。
///
/// 写入一致性策略：**乐观更新 + 失败回滚**。
/// 先改内存状态让 UI 立即响应，再异步落盘；落盘失败则回滚到上一次快照
/// 并把异常重新抛出。这样既没有"点了没反应"的延迟感，
/// 也不会出现"看起来标记了但重启后消失"的静默失败。
/// ─────────────────────────────────────────────────────────────
final watchHistoryProvider =
    AsyncNotifierProvider<WatchHistoryNotifier, WatchHistoryState>(
  WatchHistoryNotifier.new,
);

class WatchHistoryNotifier extends AsyncNotifier<WatchHistoryState> {
  /// 进度回写心跳。
  Timer? _timer;

  /// 当前播放会话的"基准记录"（含影片元数据与选集信息）。
  ///
  /// 心跳期间只更新位置与时长，其余字段沿用该基准，
  /// 避免每 5 秒重建一次完整对象图。
  WatchRecord? _sessionBase;

  int _pendingPositionMs = 0;
  int _pendingDurationMs = 0;

  /// 自上次落盘以来进度是否发生了"值得写入"的变化。
  bool _dirty = false;

  /// 防止心跳与手动 flush 重入。
  bool _flushing = false;

  WatchHistoryRepository get _repo => ref.read(watchHistoryRepositoryProvider);

  @override
  Future<WatchHistoryState> build() async {
    ref.onDispose(_disposeTimer);
    final records = await _repo.loadAll();
    return WatchHistoryState(records: records);
  }

  // ─────────────────────────────────────────────────────────
  // 状态切换
  // ─────────────────────────────────────────────────────────

  /// 把影片设为指定状态（不存在则新建）。
  ///
  /// 这是所有手动标记的统一入口：详情页的三态按钮与各列表的右键菜单
  /// 都调用它；[markWatching] / [markWatched] 等是它的语义化薄封装。
  Future<void> setStatus(Movie movie, WatchStatus status) async {
    final current = await _snapshot();
    final base = current.find(movie.id) ?? WatchRecord.wantToWatch(movie);

    await _persist(
      base.copyWith(
        sourceName: _nonEmpty(movie.sourceName, base.sourceName),
        posterUrl: _nonEmpty(movie.poster, base.posterUrl),
        year: movie.year ?? base.year,
        remarks: _nonEmpty(movie.remarks ?? '', base.remarks ?? ''),
        status: status,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> markWatching(Movie movie) =>
      setStatus(movie, WatchStatus.watching);

  Future<void> markWatched(Movie movie) =>
      setStatus(movie, WatchStatus.watched);

  /// 移出清单（删除记录）。
  Future<void> remove(String movieId) async {
    final current = await _snapshot();
    if (!current.contains(movieId)) return;

    final optimistic = current.records
        .where((r) => r.movieId != movieId)
        .toList(growable: false);

    state = AsyncValue.data(current.copyWith(records: optimistic));
    try {
      await _repo.remove(movieId);
    } catch (error, stack) {
      state = AsyncValue.data(current);
      Error.throwWithStackTrace(error, stack);
    }
  }

  /// 清空某一分栏（如「只清空已看历史」）。
  ///
  /// 返回被清空的条数。
  Future<int> removeByStatus(WatchStatus status) async {
    final current = await _snapshot();
    final optimistic = current.records
        .where((r) => r.status != status)
        .toList(growable: false);
    final removed = current.records.length - optimistic.length;

    state = AsyncValue.data(current.copyWith(records: optimistic));
    try {
      await _repo.removeByStatus(status);
      return removed;
    } catch (error, stack) {
      state = AsyncValue.data(current);
      Error.throwWithStackTrace(error, stack);
    }
  }

  /// 清空全部观影记录。
  Future<void> clear() async {
    final current = await _snapshot();
    if (current.isEmpty) return;

    state = AsyncValue.data(WatchHistoryState.empty);
    try {
      await _repo.clear();
    } catch (error, stack) {
      state = AsyncValue.data(current);
      Error.throwWithStackTrace(error, stack);
    }
  }

  // ─────────────────────────────────────────────────────────
  // 播放进度回写
  // ─────────────────────────────────────────────────────────

  /// 开始一个播放会话。
  ///
  /// 行为：
  /// * 记录立即落盘，因此"一按播放，影片就出现在『正在看』"；
  /// * 同一线路的**同一集**续播时沿用上次进度；切集则进度归零；
  /// * 启动 5 秒心跳，期间由 [reportPosition] 喂入播放器位置。
  ///
  /// [restart] 为 true 表示用户明确选择「从头播放」。此时**即使线路与集数
  /// 完全相同**也不沿用旧进度 —— 否则"从头播放"会被同集续播逻辑静默覆盖，
  /// 用户点了等于没点。
  Future<void> beginSession({
    required Movie movie,
    required PlaySource source,
    required Episode episode,
    int startPositionMs = 0,
    bool restart = false,
  }) async {
    final current = await _snapshot();
    final existing = current.find(movie.id);
    // 「从头播放」等价于"没有历史记录"。不能只把 startPositionMs 置 0——
    // 若仍带着历史走进下面的分支，旧进度会把用户的意图覆盖掉。
    final history = restart ? null : existing;

    // 默认值 = 全新起播；命中「同一线路 + 同一集」时才覆盖为续播值。
    //
    // 这里刻意**不**把条件先存成一个 bool 变量再复用：Dart 的流分析不会把
    // 该布尔变量的真值回传给被它捕获的可空变量，那样写要么编译报错，
    // 要么得补 `!` 断言。直接用一个 if 表达式最稳。
    var resumePosition = startPositionMs;
    var carriedDuration = 0;
    var initialStatus = WatchStatus.watching;

    if (history != null &&
        history.matchesEpisode(
          sourceFlag: source.flag,
          episodeIndex: episode.index,
        )) {
      resumePosition = history.lastPositionMs;
      carriedDuration = history.totalDurationMs;
      // 同一集且此前已看完 → 保持「已看」，避免刚打开就被降级为「正在看」
      if (history.status.isWatched) initialStatus = WatchStatus.watched;
    }

    final base = WatchRecord(
      movieId: movie.id,
      sourceKey: movie.sourceKey,
      vodId: movie.vodId,
      sourceName: movie.sourceName,
      title: movie.title,
      posterUrl: movie.poster,
      year: movie.year,
      remarks: movie.remarks,
      currentEpisodeTitle: episode.name,
      currentEpisodeIndex: episode.index,
      lastPositionMs: resumePosition,
      totalDurationMs: carriedDuration,
      playSourceFlag: source.flag,
      playSourceName: source.name,
      episodeUrl: episode.url,
      status: initialStatus,
      updatedAt: DateTime.now(),
      createdAt: existing?.createdAt,
    );

    _sessionBase = base;
    _pendingPositionMs = resumePosition;
    _pendingDurationMs = base.totalDurationMs;

    await _persist(base);
    // 基准已落盘，等待播放器的首个位置回调再产生 dirty 标记
    _dirty = false;
    _startTimer();
  }

  /// 播放器位置回调（高频，可每帧调用）。
  ///
  /// 这里**只更新内存样本**、不落盘：真正写盘由 5 秒心跳完成。
  /// 若位置变化不足 [AppConstants.kProgressMinDeltaMs] 则不置脏，
  /// 避免暂停状态下反复写同一条数据。
  void reportPosition({required int positionMs, required int durationMs}) {
    final base = _sessionBase;
    if (base == null) return;

    final effectiveDuration = durationMs > 0 ? durationMs : base.totalDurationMs;
    final delta = (positionMs - _pendingPositionMs).abs();

    _pendingPositionMs = positionMs;
    _pendingDurationMs = effectiveDuration;
    if (delta >= AppConstants.kProgressMinDeltaMs) _dirty = true;
  }

  /// 立即写盘（暂停 / 切集 / 页面退出时调用）。
  ///
  /// [force] 为 true 时忽略脏标记与最小变化量，用于会话结束的兜底写入。
  ///
  /// 刻意**不向上抛异常**：它可能由 `Timer` 触发，抛出会成为未捕获的异步错误。
  /// 失败时保留脏标记，下一次心跳自动重试。
  Future<void> flush({bool force = false}) async {
    final base = _sessionBase;
    if (base == null || _flushing) return;
    if (!force && !_dirty) return;

    _flushing = true;
    try {
      await _writeProgress(base: base, positionMs: _pendingPositionMs, durationMs: _pendingDurationMs);
      _dirty = false;
    } catch (_) {
      // 保留 _dirty，下个心跳重试；进度写失败不应影响播放
    } finally {
      _flushing = false;
    }
  }

  /// 结束播放会话：停心跳并补写最后一次进度。
  Future<void> endSession() async {
    _disposeTimer();
    await flush(force: true);
    _sessionBase = null;
    _pendingPositionMs = 0;
    _pendingDurationMs = 0;
    _dirty = false;
  }

  /// 一次性写入进度（无需先 [beginSession]）。
  ///
  /// 供**内嵌播放器 / 外部上报**场景使用：记录不存在时会依据 [movie] 创建，
  /// 状态按 "≥90% → 已看，否则 → 正在看" 自动流转。
  ///
  /// 与 [beginSession] + [reportPosition] 的分工：
  /// * 连续播放用会话式（一次建立基准 + 多次喂位置 + 自动心跳落盘）；
  /// * 只拿到一个时间点的场景（如切换到后台被系统回收、外部播放器回传一次
  ///   进度）用本方法，直接落一条。
  Future<void> updateProgress({
    required Movie movie,
    required int positionMs,
    required int durationMs,
    String episodeTitle = '',
    int episodeIndex = 0,
    String episodeUrl = '',
    String playSourceFlag = '',
    String playSourceName = '',
  }) async {
    final current = await _snapshot();
    final existing = current.find(movie.id) ?? WatchRecord.wantToWatch(movie);

    final base = existing.copyWith(
      sourceName: _nonEmpty(movie.sourceName, existing.sourceName),
      posterUrl: _nonEmpty(movie.poster, existing.posterUrl),
      year: movie.year ?? existing.year,
      remarks: _nonEmpty(movie.remarks ?? '', existing.remarks ?? ''),
      currentEpisodeTitle: _nonEmpty(episodeTitle, existing.currentEpisodeTitle),
      currentEpisodeIndex: episodeIndex,
      episodeUrl: _nonEmpty(episodeUrl, existing.episodeUrl),
      playSourceFlag: _nonEmpty(playSourceFlag, existing.playSourceFlag),
      playSourceName: _nonEmpty(playSourceName, existing.playSourceName),
    );

    await _writeProgress(base: base, positionMs: positionMs, durationMs: durationMs);
  }

  // ─────────────────────────────────────────────────────────
  // 查询（同步，不触发 IO）
  // ─────────────────────────────────────────────────────────

  /// 取某影片最近的观看记录。
  ///
  /// 播放页据此判断是否需要弹出「是否继续播放」：
  /// 判据是 [WatchRecord.shouldResume]（有进度、未看完）。
  ///
  /// 注意：这是**纯内存读**，冷启动首屏加载未完成时会返回 null。
  /// 需要"一定读到"的场景（如详情页起播前的续播判定）请先 await
  /// [watchHistoryProvider] 的 future 再判定。
  WatchRecord? getLastWatchRecord(String movieId) =>
      state.valueOrNull?.find(movieId);

  // ─────────────────────────────────────────────────────────
  // 内部
  // ─────────────────────────────────────────────────────────

  /// 把「基准记录 + 当前位置」合成为新记录并落盘。
  Future<void> _writeProgress({
    required WatchRecord base,
    required int positionMs,
    required int durationMs,
  }) async {
    final effectiveDuration = durationMs > 0 ? durationMs : base.totalDurationMs;

    final next = base.copyWith(
      lastPositionMs: positionMs,
      totalDurationMs: effectiveDuration,
      status: _resolveStatus(
        positionMs: positionMs,
        durationMs: effectiveDuration,
      ),
      updatedAt: DateTime.now(),
    );

    // 心跳写盘：进度几乎没变时跳过，避免无意义的状态重建
    final state0 = state.valueOrNull;
    final previous = state0?.find(next.movieId);
    if (previous != null &&
        (previous.lastPositionMs - positionMs).abs() <
            AppConstants.kProgressMinDeltaMs &&
        previous.totalDurationMs == effectiveDuration &&
        previous.status == next.status) {
      return;
    }

    await _persist(next);

    // 基准同步为最新值，使后续心跳从正确的字段出发
    if (_sessionBase != null && _sessionBase!.id == next.id) {
      _sessionBase = next;
    }
  }

  /// 状态流转规则（唯一判定点）。
  ///
  /// ```
  /// 进度 ≥ 90%  → 已看
  /// 其它        → 正在看
  /// ```
  ///
  /// 只有两个分支是有意为之：任何进度写入都意味着"用户正在看"。
  /// 因此原本的「已看」若被从头重播（进度回到低位），会自然回到「正在看」
  /// —— 这既让「继续观看」重新出现，也避免「已看」成为无法打破的终态。
  WatchStatus _resolveStatus({
    required int positionMs,
    required int durationMs,
  }) {
    final reached = durationMs > 0 &&
        positionMs / durationMs >= AppConstants.kWatchedThreshold;
    return reached ? WatchStatus.watched : WatchStatus.watching;
  }

  /// 乐观更新内存状态 + 落盘，失败回滚。
  Future<void> _persist(WatchRecord record) async {
    final current = await _snapshot();

    final others = current.records.where((r) => r.id != record.id);
    // 置顶保持 updatedAt 倒序不变量
    state = AsyncValue.data(
      current.copyWith(records: <WatchRecord>[record, ...others]),
    );

    try {
      await _repo.upsert(record);
    } catch (error, stack) {
      state = AsyncValue.data(current);
      Error.throwWithStackTrace(error, stack);
    }
  }

  /// 取当前状态；首次加载未完成时等待 [build] 结束。
  ///
  /// 必要性：若在加载完成前用空状态做乐观更新，会把磁盘上已有的记录
  /// 从内存快照里"挤掉"，导致 UI 短暂丢数据。
  Future<WatchHistoryState> _snapshot() async {
    final value = state.valueOrNull;
    if (value != null) return value;
    return await future;
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(
      AppConstants.kProgressFlushInterval,
      (_) => flush(),
    );
  }

  void _disposeTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// 仅在非空时采用新值（用于 copyWith 的"有则覆盖"语义）。
  static String _nonEmpty(String candidate, String fallback) =>
      candidate.trim().isEmpty ? fallback : candidate;
}

// ─────────────────────────────────────────────────────────────
// 派生查询（避免页面各自遍历全表）
//
// 只保留真正被页面消费的派生项 —— 未使用的 selector 属于死代码，
// 会让「这个 Provider 到底谁在用」变成需要全局搜索才能回答的问题。
// ─────────────────────────────────────────────────────────────

/// 资料库全量状态。页面直接 watch 它即可拿到三个分栏
/// （通过 [WatchHistoryState.of] / [WatchHistoryState.countOf]）。
final watchHistoryStateProvider = Provider<WatchHistoryState>((ref) {
  return ref.watch(watchHistoryProvider).valueOrNull ?? WatchHistoryState.empty;
});

/// 首页「继续观看」：正在看且进度值得续播，最多
/// [AppConstants.kResumeListLimit] 条。
final resumeListProvider = Provider<List<WatchRecord>>((ref) {
  final resumable = ref.watch(watchHistoryStateProvider).resumable;
  return resumable.take(AppConstants.kResumeListLimit).toList(growable: false);
});

/// 侧边栏「片库」角标：正在看 + 想看（不含已看）。
final watchActiveCountProvider = Provider<int>(
  (ref) => ref.watch(watchHistoryStateProvider).activeCount,
);

/// 某影片的观影记录（同步）。
///
/// 既是详情页状态按钮的数据源，也是**续播判定的唯一入口**：
/// ```dart
/// final record = ref.watch(watchRecordProvider(movieId));
/// if (record != null && record.shouldResume) { ...弹窗提示继续播放... }
/// ```
final watchRecordProvider = Provider.family<WatchRecord?, String>(
  (ref, movieId) => ref.watch(watchHistoryStateProvider).find(movieId),
);

/// 某影片当前状态（无记录时为 null）。
///
/// 想看 / 正在看 / 已看三态查询都走它，不再为每种状态各开一个
/// `is*Provider` —— 那只是同一判定的三份拷贝。
final watchStatusProvider = Provider.family<WatchStatus?, String>(
  (ref, movieId) => ref.watch(watchHistoryStateProvider).statusOf(movieId),
);
