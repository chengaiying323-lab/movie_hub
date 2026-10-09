import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../constants/app_constants.dart';
import 'playback_source.dart';
import 'playback_state.dart';
import 'player_config.dart';
import 'player_engine.dart';

/// 基于 media_kit（libmpv）的播放内核实现。
///
/// 平台说明
/// ------------------------------------------------------------------
/// * **Windows**：走 `media_kit_libs_video` 内置的 libmpv，
///   [VideoControllerConfiguration.enableHardwareAcceleration] 打开后由 mpv 自动
///   协商 D3D11VA / DXVA2；解码失败时降级为 `hwdec=no` 软解重试一次。
/// * **iOS**：**同样是 libmpv** —— `media_kit_libs_ios_video` 打包的是
///   **MPVKit**（libmpv 的 Apple 平台构建），**不是** AVPlayer / AVFoundation。
///   这个事实有两个直接后果，打包阶段必须知道：
///   1. iOS 最低系统版本被 MPVKit 的 podspec 顶到 **13.0**。
///      `ios/Podfile` 的 `platform :ios` 与 `project.pbxproj` 的
///      `IPHONEOS_DEPLOYMENT_TARGET` 是**两个地方**，必须同时改，
///      否则 `pod install` 会报 "could not find compatible versions"。
///      （脚手架默认写 12.0，所以这一步对每个新克隆的仓库都是必需的。）
///   2. 系统级画中画（PiP）只能挂载在 `AVPlayerLayer` 上，而本内核是
///      自绘纹理输出，因此**拿不到 PiP**。真要做 PiP 得换内核或自行实现。
///   另外 iOS 默认禁止明文 HTTP，而影视源站大量返回 `http://` 直链，
///   必须在 `Info.plist` 里开 `NSAppTransportSecurity` 例外；否则表现为
///   "网络请求全部失败"，且错误常被底层媒体库吞掉，UI 上只剩一句"播放失败"。
///
/// 职责边界
/// ------------------------------------------------------------------
/// 本类**只做三件事**：
/// 1. 把 [PlaybackSource] 翻译成内核调用（含请求头注入）；
/// 2. 把内核散落的多个流（position / duration / buffering / error …）
///    收敛成**单一**的 [PlaybackState] 快照；
/// 3. 兜住异常：分类失败 → 指数退避自动重试 → 额度耗尽才暴露 failed。
///
/// 它不写数据库、不切集、不换线路 —— 那些由播放页与 Riverpod 负责。
/// 这样内核可以被任何页面（预览、小窗、投屏）复用。
class MediaKitPlayerEngine implements PlayerEngine {
  MediaKitPlayerEngine({PlayerEngineConfig config = const PlayerEngineConfig()})
      : _config = config,
        _hardwareAccelerationOn = config.hardwareAcceleration {
    _player = Player(
      // 只传 title：它决定系统媒体控制中心里显示的名字。
      // 缓冲 / 超时之类的策略不在这里配，而是统一走下面的
      // `setProperty` —— `PlayerConfiguration` 的字段随版本变动较大，
      // 而 mpv 属性名是稳定接口（见 [_applyKernelProperties]）。
      configuration: const PlayerConfiguration(title: AppConstants.appName),
    );
    _controller = VideoController(
      _player,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: config.hardwareAcceleration,
      ),
    );
    _applyKernelProperties();
    _bindStreams();
  }

  final PlayerEngineConfig _config;

  late final Player _player;
  late final VideoController _controller;

  final ValueNotifier<PlaybackState> _state =
      ValueNotifier<PlaybackState>(PlaybackState.initial);

  final List<StreamSubscription<dynamic>> _subs = <StreamSubscription<dynamic>>[];

  // ── 状态标志 ────────────────────────────────────────────
  // 内核的状态是"多个独立布尔流"（playing / buffering / completed …），
  // 而 UI 需要的是"单一枚举"。这里把它们收敛成标志位，再由
  // [_resolveStatus] 唯一地计算出枚举值——状态机只有这一个判定点。
  bool _opening = false;
  bool _buffering = false;
  bool _mpvPlaying = false;
  bool _completed = false;
  bool _failed = false;

  /// 用户意图是否为"正在播放"。
  /// 与 [_mpvPlaying] 不同：缓冲中 mpv 的 playing 仍为 true，
  /// 但用户点了暂停后 playing 会变 false —— 看门狗只应在"用户想播"时运行。
  bool _intendPlay = false;

  PlaybackSource? _current;
  Duration _lastPosition = Duration.zero;

  int _attempt = 0;
  bool _hardwareAccelerationOn;
  int _pendingResumeMs = 0;
  bool _disposed = false;

  Timer? _watchdog;
  DateTime? _lastWatchdogKick;
  Timer? _retryTimer;

  // ── PlayerEngine ────────────────────────────────────────

  @override
  ValueListenable<PlaybackState> get state => _state;

  @override
  PlaybackState get current => _state.value;

  @override
  PlaybackSource? get currentSource => _current;

  @override
  bool get isDisposed => _disposed;

  @override
  Future<void> open(PlaybackSource source, {bool autoPlay = true}) async {
    if (_disposed) return;

    _current = source;
    _attempt = 0;
    _failed = false;
    _completed = false;
    _buffering = false;
    _opening = true;
    _intendPlay = autoPlay;
    _lastPosition = Duration.zero;
    _pendingResumeMs = source.isSeekable ? source.startPositionMs : 0;
    _retryTimer?.cancel();

    _state.value = _state.value.copyWith(
      position: Duration.zero,
      duration: Duration.zero,
      buffered: Duration.zero,
      clearFailure: true,
    );
    _emit();

    _kickWatchdog(_config.openTimeout, force: true);
    await _player.open(
      Media(source.url, httpHeaders: _headersFor(source)),
      play: autoPlay,
    );
  }

  @override
  Future<void> play() async {
    if (_disposed) return;
    if (_completed) {
      // mpv 在 EOF 后再次 play 的行为依版本而异，显式回到起点最稳。
      _completed = false;
      await _player.seek(Duration.zero);
    }
    _intendPlay = true;
    _kickWatchdog(_config.stallTimeout, force: true);
    _emit();
    await _player.play();
  }

  @override
  Future<void> pause() async {
    if (_disposed) return;
    _intendPlay = false;
    _clearWatchdog();
    _emit();
    await _player.pause();
  }

  @override
  Future<void> togglePlay() => _mpvPlaying ? pause() : play();

  @override
  Future<void> seek(Duration position) async {
    if (_disposed) return;
    _completed = false;
    await _player.seek(_clamp(position));
  }

  @override
  Future<void> seekBy(Duration offset) async {
    if (_disposed) return;
    await seek(_state.value.position + offset);
  }

  @override
  Future<void> setRate(double rate) async {
    if (_disposed) return;
    final value = rate < 0.25 ? 0.25 : (rate > 4.0 ? 4.0 : rate);
    await _player.setRate(value);
  }

  @override
  Future<void> setVolume(double volume) async {
    if (_disposed) return;
    final value = volume < 0 ? 0.0 : (volume > 100 ? 100.0 : volume);
    await _player.setVolume(value);
  }

  @override
  Future<void> retry() async {
    if (_disposed || _current == null) return;
    _attempt = 0;
    _failed = false;
    _opening = true;
    // 用户点了重试 = 明确想继续看，因此把播放意图重新立起来
    // （失败终态时 `_handleFailure` 会把它置为 false）。
    _intendPlay = true;
    _emit(clearFailure: true);
    _kickWatchdog(_config.openTimeout, force: true);
    await _reopen();
  }

  @override
  Future<void> stop() async {
    if (_disposed) return;
    _retryTimer?.cancel();
    _clearWatchdog();
    _current = null;
    _attempt = 0;
    _opening = false;
    _buffering = false;
    _mpvPlaying = false;
    _completed = false;
    _failed = false;
    _intendPlay = false;
    _pendingResumeMs = 0;
    _lastPosition = Duration.zero;
    await _player.stop();
    _state.value = _state.value.copyWith(
      position: Duration.zero,
      duration: Duration.zero,
      buffered: Duration.zero,
      clearFailure: true,
    );
    _emit();
  }

  @override
  Widget buildVideo({BoxFit fit = BoxFit.contain}) => Video(
        controller: _controller,
        fit: fit,
        controls: NoVideoControls,
      );

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _watchdog?.cancel();
    _retryTimer?.cancel();
    _watchdog = null;
    _retryTimer = null;

    await Future.wait(_subs.map((s) => s.cancel()));
    _subs.clear();

    // 先释放渲染面再释放播放器：VideoController 持有 Player 的原生句柄，
    // 反序释放会触发 mpv 侧对已销毁纹理的写入。
    await _controller.dispose();
    await _player.dispose();
    _state.dispose();
  }

  // ── 初始化细节 ──────────────────────────────────────────

  /// 把策略配置落到 mpv 原生属性上。
  ///
  /// 为什么用 [Player.setProperty] 而不是全塞进 `VideoControllerConfiguration`：
  /// 一是该类的字段随版本变动较大，直接写属性更稳定；
  /// 二是属性可以**运行期修改**（如解码失败后关掉 hwdec 再重开），
  /// 而 `VideoControllerConfiguration` 只在构造时生效，改它得重建整个渲染面。
  void _applyKernelProperties() {
    // libmpv 默认无限等待网络，弱网下表现为"永久缓冲"而非报错。
    unawaited(_player.setProperty('network-timeout', '${_config.networkTimeoutSec}'));
    unawaited(_player.setProperty('demuxer-max-bytes', _config.demuxerMaxBytes));
    unawaited(_player.setProperty('demuxer-max-back-bytes', _config.demuxerMaxBackBytes));
    // 允许 lavf 层对 HTTP 分片做透明重连，兜住 HLS 的瞬时断流。
    unawaited(_player.setProperty(
      'stream-lavf-o',
      'reconnect=1,reconnect_streamed=1,reconnect_delay_max=4',
    ));
    if (!_config.hardwareAcceleration) {
      unawaited(_player.setProperty('hwdec', 'no'));
    }
  }

  void _bindStreams() {
    final streams = _player.stream;
    _subs.addAll(<StreamSubscription<dynamic>>[
      streams.position.listen(_onPosition),
      streams.duration.listen(_onDuration),
      streams.buffering.listen(_onBuffering),
      streams.playing.listen(_onPlaying),
      streams.completed.listen(_onCompleted),
      streams.error.listen(_onError),
      streams.rate.listen((r) => _emit(rate: r)),
      streams.volume.listen((v) => _emit(volume: v)),
      streams.width.listen((w) => _emit(videoWidth: w)),
      streams.height.listen((h) => _emit(videoHeight: h)),
      streams.buffer.listen((ranges) {
        // 这里刻意不写显式类型标注：`buffer` 下发的是内核自己的缓冲区间类型，
        // 由类型推断处理即可，避免把内核的辅助类型名写进我们的代码里
        // —— 那会让"换内核"多出一处需要改的地方。
        final position = _state.value.position;
        var best = Duration.zero;
        for (final range in ranges) {
          // 取"当前位置所在区间"的末尾。mpv 可能同时给出多个不连续区间
          // （seek 之后旧缓存与新区块并存），无脑取最后一个会画错进度条。
          if (position >= range.start && position <= range.end) {
            best = range.end;
            break;
          }
          if (range.start <= position && range.end > best) {
            best = range.end;
          }
        }
        _emit(buffered: best);
      }),
    ]);
  }

  // ── 流事件处理 ──────────────────────────────────────────

  void _onPosition(Duration position) {
    if (position > _lastPosition) {
      _lastPosition = position;
      // 位置在推进 = 有数据在流 → 断流看门狗重新计时
      _kickWatchdog(_config.stallTimeout);
    }
    _opening = false;
    _tryApplyResume();
    _emit(position: position);
  }

  void _onDuration(Duration duration) {
    _opening = false;
    _emit(duration: duration);
    _tryApplyResume();
  }

  void _onBuffering(bool value) {
    _buffering = value;
    if (_intendPlay) {
      // 缓冲期间也必须维持看门狗：这正是"断流"最典型的形态
      _kickWatchdog(_config.stallTimeout);
    }
    _emit();
  }

  void _onPlaying(bool value) {
    _mpvPlaying = value;
    if (value) _opening = false;
    _emit();
  }

  void _onCompleted(bool value) {
    if (value) {
      _completed = true;
      _intendPlay = false;
      _clearWatchdog();
    }
    _emit();
  }

  void _onError(String message) {
    if (_disposed || message.trim().isEmpty) return;

    // 播放中途的分片失败：mpv 常常能自行重连，一次瞬时 404 不该把整集判死。
    // 交给看门狗判断"位置是否真的停住了"，停住了才升级为失败。
    if (_mpvPlaying && _lastPosition > Duration.zero && _current?.isSeekable == true) {
      if (_intendPlay) _kickWatchdog(_config.stallTimeout);
      return;
    }

    _handleFailure(message);
  }

  // ── 失败与重试 ──────────────────────────────────────────

  /// 唯一的失败入口：分类 → 决定是否自动重试 → 否则进入 failed 终态。
  void _handleFailure(Object error) {
    if (_disposed) return;
    _clearWatchdog();

    final source = _current;
    final failure = PlaybackFailure.fromRaw(
      error,
      attempt: _attempt,
      maxAttempts: _config.maxRetryAttempts,
      url: source?.url,
    );
    final kind = failure.kind;

    // 解码失败的首要嫌疑是硬解兼容性：先关硬解，再给一次机会。
    // 这一步在重试判定之前做，才能让紧接着的重试用软解跑。
    if (kind == PlaybackFailureKind.decode && _hardwareAccelerationOn) {
      _hardwareAccelerationOn = false;
      unawaited(_player.setProperty('hwdec', 'no'));
    }

    // 三个条件各管一件事，缺一不可：
    // * `canRetry`        —— 这类错误重试有没有意义（403 重试必然还是 403）；
    // * `hasRetryBudget`  —— 还有没有次数；
    // * `_intendPlay`     —— 用户是否仍在等这集播起来（已暂停时不必后台重连）。
    final canAutoRetry = failure.canRetry &&
        failure.hasRetryBudget &&
        _intendPlay &&
        source != null;

    if (canAutoRetry) {
      _attempt++;
      _failed = false;
      _opening = true;
      final delay = _backoff(_attempt);
      _emit(
        failure: failure.copyWith(
          attempt: _attempt,
          message: '${kind.label}，'
              '${(delay.inMilliseconds / 1000).toStringAsFixed(1)} 秒后自动重试'
              '（第 $_attempt/${_config.maxRetryAttempts} 次）',
        ),
      );
      _retryTimer?.cancel();
      _retryTimer = Timer(delay, () => unawaited(_reopen()));
      return;
    }

    _failed = true;
    _intendPlay = false;
    _emit(failure: failure);
  }

  Future<void> _reopen() async {
    final source = _current;
    if (_disposed || source == null) return;
    _kickWatchdog(_config.openTimeout, force: true);
    await _player.open(
      Media(source.url, httpHeaders: _headersFor(source)),
      play: _intendPlay,
    );
  }

  /// 指数退避：`base × 2^(n-1)`，上限 [PlayerEngineConfig.retryMaxDelay]。
  Duration _backoff(int attempt) {
    final base = _config.retryBaseDelay.inMilliseconds;
    final maxMs = _config.retryMaxDelay.inMilliseconds;
    final raw = (base * math.pow(2, attempt - 1)).round();
    return Duration(milliseconds: raw.clamp(base, maxMs).toInt());
  }

  // ── 看门狗 ──────────────────────────────────────────────

  /// 重置"无进展"计时器。
  ///
  /// 这是本内核里最容易被忽略但最关键的一环：
  /// `stream.error` 只能覆盖"内核明确报错"的情况，而弱网/防盗链最常见的
  /// 失败形态是 **既不报错也不推进**（TCP 连上了但服务端不发数据）。
  /// 没有看门狗，UI 会永远停在转圈上。
  ///
  /// [force] 用于起播 / 重试这类必须拿到完整超时的场景；
  /// 位置推进触发的重置走节流 —— 位置回调可达 10Hz，每秒重建 10 个 Timer
  /// 毫无意义，而节流带来的最坏后果只是"晚 1 秒发现断流"。
  void _kickWatchdog(Duration delay, {bool force = false}) {
    if (_disposed || !_intendPlay) {
      _watchdog?.cancel();
      _watchdog = null;
      _lastWatchdogKick = null;
      return;
    }

    final now = DateTime.now();
    final last = _lastWatchdogKick;
    if (!force &&
        _watchdog != null &&
        last != null &&
        now.difference(last) < const Duration(seconds: 1)) {
      return;
    }

    _watchdog?.cancel();
    _lastWatchdogKick = now;
    _watchdog = Timer(delay, () {
      _watchdog = null;
      _handleFailure(
        'Loading timed out: no data received for '
        '${delay.inSeconds}s (position stalled at '
        '${_lastPosition.inSeconds}s)',
      );
    });
  }

  void _clearWatchdog() {
    _watchdog?.cancel();
    _watchdog = null;
    _lastWatchdogKick = null;
  }

  // ── 工具 ────────────────────────────────────────────────

  /// 续播定位。
  ///
  /// 必须在**拿到时长之后**执行：多数内核在 open 完成前 Seek 会被丢弃，
  /// 这也是 [PlaybackSource.startPositionMs] 不被塞进 open 参数的原因。
  void _tryApplyResume() {
    final pending = _pendingResumeMs;
    if (pending <= 0) return;
    final total = _state.value.duration;
    if (total <= Duration.zero) return;

    _pendingResumeMs = 0;
    final target = Duration(milliseconds: pending);
    // 距离结尾不足 5 秒：用户实际上已经看完了，停在片尾不如从头开始
    if (target >= total - const Duration(seconds: 5)) return;

    unawaited(_player.seek(target));
    _emit(position: target);
  }

  /// 组装下发给内核的请求头。
  ///
  /// 优先级：源声明 > 全局默认 > 兜底 UA。
  /// 兜底 UA 不能省：大量 CDN 对空 UA 直接返回 403。
  Map<String, String> _headersFor(PlaybackSource source) {
    final merged = <String, String>{};
    merged.addAll(_config.defaultHeaders);
    merged.addAll(source.headers);

    final hasUserAgent =
        merged.keys.any((key) => key.toLowerCase() == 'user-agent');
    if (!hasUserAgent) {
      merged['User-Agent'] = AppConstants.defaultUserAgent;
    }
    return merged;
  }

  Duration _clamp(Duration position) {
    final total = _state.value.duration;
    if (position < Duration.zero) return Duration.zero;
    if (total > Duration.zero && position > total) return total;
    return position;
  }

  void _emit({
    Duration? position,
    Duration? duration,
    Duration? buffered,
    double? rate,
    double? volume,
    int? videoWidth,
    int? videoHeight,
    PlaybackFailure? failure,
    bool clearFailure = false,
  }) {
    if (_disposed) return;
    // ValueNotifier 内部用 == 判重（PlaybackState 已实现值相等），
    // 因此重复上报同一个状态不会触发 UI 重建。
    _state.value = _state.value.copyWith(
      status: _resolveStatus(),
      position: position,
      duration: duration,
      buffered: buffered,
      rate: rate,
      volume: volume,
      videoWidth: videoWidth,
      videoHeight: videoHeight,
      failure: failure,
      clearFailure: clearFailure,
    );
  }

  /// 状态机唯一判定点。
  ///
  /// 优先级顺序即为语义：失败 > 已播完 > 打开中 > 缓冲中 > 播放中 > 暂停。
  /// `idle` 只在"从未打开过任何媒体"时出现（`_current == null`）。
  PlaybackStatus _resolveStatus() {
    if (_failed) return PlaybackStatus.failed;
    if (_completed) return PlaybackStatus.completed;
    if (_opening) return PlaybackStatus.opening;
    if (_buffering) return PlaybackStatus.buffering;
    if (_mpvPlaying) return PlaybackStatus.playing;
    if (_current == null) return PlaybackStatus.idle;
    return PlaybackStatus.paused;
  }
}
