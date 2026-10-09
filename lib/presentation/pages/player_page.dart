import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/player/player.dart';
import '../../data/player/playback_request_builder.dart';
import '../../domain/entities/episode.dart';
import '../../domain/entities/movie.dart';
import '../../domain/entities/play_source.dart';
import '../../domain/entities/source_config.dart';
import '../../domain/entities/watch_record.dart';
import '../providers/player_providers.dart';
import '../providers/source_providers.dart';
import '../providers/watch_history_providers.dart';
import '../theme/player_palette.dart';
import '../widgets/player/player_widgets.dart';

/// 视频播放页。
///
/// 这是第四阶段的汇聚点：**内核 + 历史 + UI** 三者在这里闭环。
///
/// 时序总览
/// ------------------------------------------------------------------
/// ```
/// initState
///   ├─ 创建内核（复用播放页生命周期）
///   ├─ 锁横屏（移动端）/ 保持原状（桌面端）
///   └─ postFrame → _bootstrap()
///                    ├─ 解析线路与选集（缺省回退到第一条可用线路）
///                    ├─ 读观看记录（冷启动竞态安全）
///                    ├─ 命中「同线路同集且未看完」→ 暗色续播浮层
///                    ├─ beginSession()  ← 记录立即落盘，「正在看」立刻生效
///                    └─ engine.open()   ← 携带防盗链请求头
///
/// 播放中
///   └─ engine.state 监听 → reportPosition()  ← 5 秒心跳由 Notifier 负责落盘
///
/// 结束 / 退出
///   ├─ 播完 → flush(force: true)  ← 位置 ≥90%，状态自动转「已看」
///   └─ dispose → endSession()     ← 强制补写最后一个位置
/// ```
///
/// 为什么进度监听不经过 Riverpod
/// ------------------------------------------------------------------
/// 内核的位置回调可达 10Hz。若把它桥接进 Riverpod 全局 state，整棵订阅树
/// 会按帧重建。这里直接挂在 `engine.state` 这个 `ValueListenable` 上，
/// 回调里只做"赋值给 Notifier 的内存样本"这一件极轻的事，
/// UI 侧则由 `ValueListenableBuilder` 把重建范围压在时间标签与进度条内部。
class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({
    super.key,
    required this.movie,
    required this.sourceFlag,
    this.episodeIndex = 0,
    this.autoPlay = true,
  });

  /// 影片（必须携带 [Movie.sources]，播放页据此提供选集与换线路）。
  final Movie movie;

  /// 初始线路标志（`PlaySource.flag`）。
  final String sourceFlag;

  /// 初始集序号（`Episode.index`）。
  final int episodeIndex;

  /// 是否自动起播。false 时先预加载，等用户按播放。
  final bool autoPlay;

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  /// 控制层自动隐藏延时。
  static const Duration _autoHideDelay = Duration(seconds: 4);

  late final PlayerEngine _engine;
  late final WatchHistoryNotifier _history;

  PlaySource? _source;
  Episode? _episode;
  PlaybackSource? _playback;
  String? _bootMessage;

  Timer? _hideTimer;
  DateTime? _lastRestartAt;
  bool _controlsVisible = true;
  bool _locked = false;
  bool _fullscreen = false;
  bool _sessionStarted = false;
  bool _completionFlushed = false;
  bool _disposed = false;

  bool get _isDesktopPlatform =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;

  @override
  void initState() {
    super.initState();
    _engine = ref.read(playerEngineFactoryProvider)();
    _history = ref.read(watchHistoryProvider.notifier);
    _engine.state.addListener(_onPlaybackTick);

    // 播放期间不允许息屏。这是播放器的基本礼仪：
    // 一集 45 分钟必然超过系统默认息屏时间。
    unawaited(WakelockPlus.enable());

    if (!_isDesktopPlatform) {
      // 移动端进入播放页即锁横屏 + 沉浸式：竖屏看视频只有一个后果——
      // 画面被压成中间一条窄带。
      _fullscreen = true;
      unawaited(_applyImmersiveLandscape());
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _disposed = true;
    _hideTimer?.cancel();
    _engine.state.removeListener(_onPlaybackTick);

    // 下面几个动作在 dispose 里都无法 await，只能 fire-and-forget。
    // `endSession()` 用的是通过 reportPosition 喂进去的**内存样本**
    // （不依赖内核仍活着），所以先关会话、后销毁内核不会有竞态。
    unawaited(_history.endSession());
    unawaited(_engine.dispose());
    unawaited(WakelockPlus.disable());

    if (!_isDesktopPlatform) {
      unawaited(_restoreSystemChrome());
    } else if (_fullscreen) {
      unawaited(windowManager.setFullScreen(false));
    }

    super.dispose();
  }

  // ── 启动流程 ────────────────────────────────────────────

  Future<void> _bootstrap() async {
    final usable = _usableSources;
    if (usable.isEmpty) {
      setState(() => _bootMessage = '该影片暂无可播放线路。');
      return;
    }

    final source = usable.firstWhere(
      (s) => s.flag == widget.sourceFlag,
      orElse: () => usable.first,
    );
    final episode = source.episodeByIndex(widget.episodeIndex);
    if (episode == null) {
      setState(() => _bootMessage = '该线路暂无可播放的选集。');
      return;
    }

    setState(() {
      _source = source;
      _episode = episode;
    });

    // ── ① 续播询问 ────────────────────────────────────────
    var startPositionMs = 0;
    var restart = false;

    final record = await _resolveLastRecord(widget.movie.id);
    if (_disposed) return;

    // 注意这里先落成一个局部可空变量再判空：`shouldPromptResume(record)`
    // 是函数调用，Dart 不会因为它的返回值而把 `record` 提升为非空，
    // 直接写 `record!.lastPositionMs` 会在后面使用时编译不过。
    final candidate = shouldPromptResume(record) ? record : null;

    if (candidate != null &&
        candidate.matchesEpisode(
          sourceFlag: source.flag,
          episodeIndex: episode.index,
        )) {
      final choice = await showPlayerResumeOverlay(context, record: candidate);
      if (_disposed) return;

      switch (choice) {
        case ResumeChoice.resume:
          startPositionMs = candidate.lastPositionMs;
        case ResumeChoice.restart:
          restart = true;
        case ResumeChoice.cancel:
          // 用户明确取消 = 不想现在看，直接退出播放页，
          // 而不是"悄悄从头开始播"。同样用显式 pop 绕过 PopScope。
          Navigator.of(context).pop();
          return;
      }
    }

    await _startPlayback(
      source: source,
      episode: episode,
      startPositionMs: startPositionMs,
      restart: restart,
    );
  }

  /// 建立会话并打开媒体。
  ///
  /// [isSwitch] 表示这是一次线路/选集切换：需要先 `stop()` 清掉旧媒体，
  /// 但**复用同一个内核**（重建内核会有 300ms 级黑屏，做不到"无缝"）。
  Future<void> _startPlayback({
    required PlaySource source,
    required Episode episode,
    int startPositionMs = 0,
    bool restart = false,
    bool isSwitch = false,
  }) async {
    setState(() {
      _source = source;
      _episode = episode;
      _locked = false;
      _controlsVisible = true;
    });
    _sessionStarted = false;
    _completionFlushed = false;

    if (isSwitch) {
      await _engine.stop();
      if (_disposed) return;
    }

    // ── ② 建立播放会话 ────────────────────────────────────
    // beginSession 内部会对「同线路同集」沿用旧进度；这里传入的
    // startPositionMs 与它遵循同一条规则（WatchRecord.matchesEpisode），
    // 因此记录里的位置与播放器实际起播位置不会漂移。
    try {
      await _history.beginSession(
        movie: widget.movie,
        source: source,
        episode: episode,
        startPositionMs: startPositionMs,
        restart: restart,
      );
      _sessionStarted = true;
    } catch (_) {
      // 记录失败不应阻断播放本身
    }

    // ── ③ 打开内核 ────────────────────────────────────────
    final request = buildPlaybackRequest(
      movie: widget.movie,
      source: source,
      episode: episode,
      config: _configFor(source),
      startPositionMs: startPositionMs,
    );

    if (_disposed) return;
    setState(() => _playback = request.source);
    _restartHideTimer(force: true);
    await _engine.open(request.source, autoPlay: widget.autoPlay);
  }

  /// 读取上次观看记录。
  ///
  /// [WatchHistoryNotifier.getLastWatchRecord] 是纯内存读，冷启动首屏
  /// Hive 加载未完成时必然返回 null，表现为"明明有进度却不弹续播"。
  /// 因此不命中时再等一次首屏加载（读本地 Box，耗时极短）。
  Future<WatchRecord?> _resolveLastRecord(String movieId) async {
    final cached = _history.getLastWatchRecord(movieId);
    if (cached != null) return cached;
    try {
      final loaded = await ref.read(watchHistoryProvider.future);
      return loaded.find(movieId);
    } catch (_) {
      return null;
    }
  }

  // ── 进度回写 ────────────────────────────────────────────

  /// 内核状态回调（可达 10Hz）。
  ///
  /// 这里只做两件极轻的事：喂给会话样本、处理播完。真正的落盘由
  /// [WatchHistoryNotifier] 的 5 秒心跳完成，避免高频磁盘 IO。
  void _onPlaybackTick() {
    if (_disposed) return;
    final state = _engine.current;
    final status = state.status;

    if (_sessionStarted && state.duration > Duration.zero) {
      _history.reportPosition(
        positionMs: state.position.inMilliseconds,
        durationMs: state.duration.inMilliseconds,
      );
    }

    if (status == PlaybackStatus.completed) {
      if (!_completionFlushed) {
        _completionFlushed = true;
        // 播完这一下的位置通常已在 90% 以上，强制写盘即完成
        // 「已看」流转，不用等下个心跳（可能用户已经准备退出）。
        unawaited(_history.flush(force: true));
      }
    } else {
      _completionFlushed = false;
    }

    // 暂停 / 失败 / 播完时控制层不应再自动隐藏
    if (status == PlaybackStatus.paused ||
        status == PlaybackStatus.failed ||
        status == PlaybackStatus.completed) {
      _hideTimer?.cancel();
      _hideTimer = null;
      if (!_controlsVisible && mounted) {
        setState(() => _controlsVisible = true);
      }
    }
  }

  // ── 控制层显隐 ──────────────────────────────────────────

  void _toggleControls() {
    if (_locked) return;
    if (!mounted) return;
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _restartHideTimer(force: true);
  }

  void _onUserActivity() {
    if (_locked) return;
    if (!_controlsVisible && mounted) setState(() => _controlsVisible = true);
    _restartHideTimer();
  }

  /// 重置"控制层自动隐藏"倒计时。
  ///
  /// [force] 用于明确的操作（点按显示、切集起播），必须拿到完整的 4 秒；
  /// 不传则走节流——鼠标悬停回调可达 60Hz，每秒重建 60 个 `Timer`
  /// 毫无意义，最多让控制层多显示 250ms，用户完全无感。
  void _restartHideTimer({bool force = false}) {
    if (_locked) {
      _hideTimer?.cancel();
      _hideTimer = null;
      _lastRestartAt = null;
      return;
    }

    final status = _engine.current.status;
    if (status == PlaybackStatus.paused ||
        status == PlaybackStatus.failed ||
        status == PlaybackStatus.completed) {
      // 暂停 / 报错 / 播完时用户正在做决定，控制层不该自己消失
      _hideTimer?.cancel();
      _hideTimer = null;
      _lastRestartAt = null;
      return;
    }

    final now = DateTime.now();
    final last = _lastRestartAt;
    if (!force &&
        _hideTimer != null &&
        last != null &&
        now.difference(last) < const Duration(milliseconds: 250)) {
      return;
    }

    _hideTimer?.cancel();
    _lastRestartAt = now;
    _hideTimer = Timer(_autoHideDelay, () {
      _hideTimer = null;
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _toggleLock() {
    if (!mounted) return;
    setState(() {
      _locked = !_locked;
      _controlsVisible = !_locked;
    });
    _restartHideTimer(force: true);
  }

  // ── 全屏 / 方向 ─────────────────────────────────────────

  Future<void> _toggleFullscreen() async {
    if (_isDesktopPlatform) {
      final next = !_fullscreen;
      setState(() => _fullscreen = next);
      await windowManager.setFullScreen(next);
      return;
    }

    setState(() => _fullscreen = !_fullscreen);
    if (_fullscreen) {
      await _applyImmersiveLandscape();
    } else {
      await _restoreSystemChrome();
    }
  }

  /// 移动端：锁定横屏 + 沉浸式（隐藏状态栏与 Home 指示条）。
  Future<void> _applyImmersiveLandscape() async {
    await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  /// 恢复系统 UI 与方向自由。
  ///
  /// 退出播放页必须还原，否则回到首页后界面仍被锁在横屏 ——
  /// 这是移动端最容易漏掉、用户又最反感的一类问题。
  Future<void> _restoreSystemChrome() async {
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  // ── 选集 / 换线路 ───────────────────────────────────────

  Future<void> _openEpisodes() async {
    final source = _source;
    final episode = _episode;
    if (source == null || episode == null) return;

    final picked = await showEpisodeDrawer(
      context,
      episodes: source.episodes,
      currentIndex: episode.index,
      sourceName: source.name,
      title: '选集 · ${widget.movie.title}',
    );
    if (picked == null || _disposed) return;
    if (picked.index == episode.index) return;
    await _switchEpisode(picked);
  }

  Future<void> _openSources() async {
    final usable = _usableSources;
    if (usable.isEmpty) return;

    final picked = await showSourceDrawer(
      context,
      sources: usable,
      currentFlag: _source?.flag,
      currentEpisodeIndex: _episode?.index,
    );
    if (picked == null || _disposed) return;
    if (picked.flag == _source?.flag) return;
    await _switchSource(picked);
  }

  /// 切集。
  ///
  /// 进度归零（换集就是从这一集开头看），但会沿用**当前会话已记录的进度基准**
  /// —— 具体由 `beginSession` 按「同线路同集」规则判定：这是新的一集，
  /// 规则不命中，因此自然从 0 开始。
  Future<void> _switchEpisode(Episode next) async {
    final source = _source;
    if (source == null) return;
    await _startPlayback(source: source, episode: next, isSwitch: true);
  }

  /// 换线路。
  ///
  /// **尽最大努力保留观看位置**：若新线路上存在同一序号的集，
  /// 且本地记录的正是这一集，则续着看，而不是把用户退回片头。
  Future<void> _switchSource(PlaySource next) async {
    final current = _episode;
    final episode = next.episodeByIndex(current?.index ?? widget.episodeIndex);
    if (episode == null) return;

    var startPositionMs = 0;
    final record = _history.getLastWatchRecord(widget.movie.id);
    if (record != null &&
        record.matchesEpisode(
          sourceFlag: next.flag,
          episodeIndex: episode.index,
        )) {
      startPositionMs = record.lastPositionMs;
    }

    await _startPlayback(
      source: next,
      episode: episode,
      startPositionMs: startPositionMs,
      isSwitch: true,
    );
  }

  // ── 工具 ────────────────────────────────────────────────

  List<PlaySource> get _usableSources =>
      widget.movie.sources.where((s) => s.hasPlayable).toList(growable: false);

  /// 取该线路所属数据源的配置 —— 防盗链请求头的唯一来源。
  ///
  /// `PlaySource.fromSourceKey` 可能为 null（聚合层合并跨源条目时未回填），
  /// 这时回退到影片自身的 `sourceKey`。这条回退链只应存在一处，
  /// 否则将来加"按线路域名猜源"之类的策略时必然漏改。
  SourceConfig? _configFor(PlaySource source) {
    final key = (source.fromSourceKey ?? widget.movie.sourceKey).trim();
    if (key.isEmpty) return null;
    return ref.read(sourceConfigByKeyProvider(key));
  }

  String _subtitleOf(PlaySource source, Episode episode) {
    final kind = _playback?.effectiveKind;
    final parts = <String>[source.name, episode.name];
    if (kind != null) parts.add(kind.label);
    parts.add('${source.episodeCount} 集');
    return parts.join(' · ');
  }

  void _handleClose() {
    // 刻意用 `pop()` 而不是 `maybePop()`：覆盖层上的返回箭头是**明确的**
    // "退出播放"意图。`maybePop()` 会被上面的 PopScope 拦下（全屏/锁屏时
    // canPop 为 false），变成"先退出全屏"——用户按两次才关得掉，
    // 而系统返回键走的才是"先退全屏"这套语义。两者分工明确。
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final source = _source;
    final episode = _episode;

    return PopScope(
      // 系统返回键的第一语义：全屏 / 锁屏时是"退出全屏 / 解锁"，
      // 而不是"关掉播放页"——后者会让用户在一次误触中丢掉整集进度。
      //
      // 注：`onPopInvoked` 是 PopScope 最初的 API，在 SDK ≥3.24 上会
      // 提示弃用（建议换 `onPopInvokedWithResult`）。这里刻意保留它，
      // 因为 pubspec 声明的最低版本是 3.22，而新 API 在 3.24 才出现——
      // 用旧 API 只会多一条弃用提示，用新 API 会直接编译不过。
      canPop: !_locked && !_fullscreen,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (_locked) {
          _toggleLock();
        } else {
          unawaited(_toggleFullscreen());
        }
      },
      child: Scaffold(
        backgroundColor: PlayerPalette.videoBackground,
        body: source == null || episode == null
            ? _UnavailableView(
                message: _bootMessage,
                onClose: _handleClose,
              )
            : VideoPlayerComponent(
                engine: _engine,
                controlsVisible: _controlsVisible,
                onToggleControls: _toggleControls,
                onUserActivity: _onUserActivity,
                onErrorRetry: () => unawaited(_engine.retry()),
                onErrorSwitchSource: _usableSources.length > 1
                    ? () => unawaited(_openSources())
                    : null,
                onErrorExit: _handleClose,
                overlay: ControlsOverlay(
                  engine: _engine,
                  title: widget.movie.title,
                  subtitle: _subtitleOf(source, episode),
                  onClose: _handleClose,
                  onOpenEpisodes: source.episodes.length > 1
                      ? () => unawaited(_openEpisodes())
                      : null,
                  onOpenSources: _usableSources.length > 1
                      ? () => unawaited(_openSources())
                      : null,
                  onToggleFullscreen: () => unawaited(_toggleFullscreen()),
                  isFullscreen: _fullscreen,
                  onToggleLock: _isDesktopPlatform ? null : _toggleLock,
                  locked: _locked,
                  topInset: padding.top,
                  bottomInset: padding.bottom,
                ),
              ),
      ),
    );
  }
}

/// 影片不可播放 / 尚在准备时的占位页。
///
/// [message] 为空表示"正在准备"（首次进入、续播浮层尚未决断），
/// 此时给一个加载指示而不是错误图标 —— 把正常流程渲染成错误，
/// 会让用户以为出了问题而反复重试。
class _UnavailableView extends StatelessWidget {
  const _UnavailableView({required this.onClose, this.message});

  final VoidCallback onClose;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final preparing = message == null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (preparing)
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    PlayerPalette.accent,
                  ),
                ),
              )
            else
              const Icon(
                Icons.videocam_off_outlined,
                size: 40,
                color: PlayerPalette.inkFaint,
              ),
            const SizedBox(height: 16),
            Text(
              message ?? '正在准备播放…',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.6,
                color: PlayerPalette.inkSecondary,
              ),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: onClose,
              style: TextButton.styleFrom(
                foregroundColor: PlayerPalette.accent,
              ),
              child: const Text('返回'),
            ),
          ],
        ),
      ),
    );
  }
}
