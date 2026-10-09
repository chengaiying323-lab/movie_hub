import 'package:meta/meta.dart';

/// 播放状态机。
///
/// ```
///            open()
///   idle ─────────────► opening
///     ▲                   │ 首帧/时长就绪
///     │  stop()           ▼
///     │              ┌─────────┐  play()   ┌──────────┐
///     └──────────────│ paused  │◄─────────►│ playing  │
///                    └─────────┘  pause()  └────┬─────┘
///                         ▲                     │ 缓冲不足
///                         │                     ▼
///                         │              ┌────────────┐
///                         └──────────────│ buffering  │
///                                        └────────────┘
///   任意状态 ──不可恢复错误──► failed
///   playing  ──播放到末尾──► completed
/// ```
///
/// 注意 `buffering` 是**独立状态**而非 `playing` 的一个布尔位：
/// 「卡住了」和「正常播放」在 UI 上的表现完全不同（前者要出加载圈并
/// 启动断流检测计时器），用一个布尔位表达会让调用方到处写
/// `if (playing && buffering)` 这类容易写错的组合判断。
enum PlaybackStatus {
  idle('待播放'),
  opening('正在打开'),
  buffering('缓冲中'),
  playing('播放中'),
  paused('已暂停'),
  completed('已播完'),
  failed('播放失败');

  const PlaybackStatus(this.label);

  final String label;
}

/// 播放失败的原因分类。
///
/// 为什么必须分类而不是直接展示内核原始报错：
/// 用户能做的动作只有三种 —— **重试**、**换线路**、**放弃**。
/// 分类的作用就是决定这三种动作里哪些该高亮：
/// * 403/404/鉴权失败 → 重试几乎无用，应主推「换线路」；
/// * 超时/断流 → 主推「重试」；
/// * 格式不支持 → 两者都无用，应提示"该源不可用"。
enum PlaybackFailureKind {
  /// 网络不可达 / 超时 / DNS 失败。
  network('网络异常', retryable: true, switchSource: false),

  /// 403 / 401：防盗链、鉴权失败、签名过期。
  forbidden('播放被拒绝（403）', retryable: false, switchSource: true),

  /// 404：资源已失效或已被删除。
  notFound('资源不存在（404）', retryable: false, switchSource: true),

  /// 播放地址是需要二次解析的页面，而非直链。
  parseFailed('播放地址需要解析', retryable: false, switchSource: true),

  /// 容器/编码不被支持。
  unsupported('格式不支持', retryable: false, switchSource: true),

  /// 解码失败（硬件解码兼容性问题，可尝试软解重试）。
  decode('解码失败', retryable: true, switchSource: true),

  /// 拉流超时 / 长时间无数据（弱网）。
  timeout('加载超时', retryable: true, switchSource: false),

  /// 无法归类。
  unknown('播放失败', retryable: true, switchSource: true);

  const PlaybackFailureKind(
    this.label, {
    required this.retryable,
    required this.switchSource,
  });

  /// 面向用户的短标签。
  final String label;

  /// 是否值得自动重试。
  final bool retryable;

  /// 是否建议用户改用其它线路。
  final bool switchSource;
}

/// 播放失败详情。
@immutable
class PlaybackFailure {
  const PlaybackFailure({
    required this.kind,
    required this.message,
    this.attempt = 0,
    this.maxAttempts = 0,
    this.rawError,
  });

  final PlaybackFailureKind kind;

  /// 面向用户的一句话说明。
  final String message;

  /// 已自动重试的次数（0 表示尚未重试）。
  final int attempt;

  /// 自动重试上限。
  final int maxAttempts;

  /// 内核原始报错（折叠显示，供用户反馈问题时复制）。
  final String? rawError;

  bool get canRetry => kind.retryable;
  bool get canSwitchSource => kind.switchSource;

  /// 是否还有自动重试余额。
  bool get hasRetryBudget => attempt < maxAttempts;

  /// 面板标题。
  String get title => kind.label;

  /// 面板副标题：给出"下一步该做什么"。
  String get hint {
    switch (kind) {
      case PlaybackFailureKind.forbidden:
        return '该线路有防盗链或鉴权限制，建议切换到其它线路。';
      case PlaybackFailureKind.notFound:
        return '该线路的播放地址已失效，建议切换到其它线路。';
      case PlaybackFailureKind.parseFailed:
        return '该线路返回的是页面地址而非直链，本站暂不支持解析，请切换线路。';
      case PlaybackFailureKind.unsupported:
        return '当前内核无法解码该格式，建议切换线路或更换播放器内核。';
      case PlaybackFailureKind.decode:
        return '可能是硬件解码兼容性问题，已尝试自动重试，仍失败请切换线路。';
      case PlaybackFailureKind.timeout:
        return '网络较慢或源站响应超时，可重试或切换线路。';
      case PlaybackFailureKind.network:
        return '请检查网络连接后重试。';
      case PlaybackFailureKind.unknown:
        return '可重试一次；若仍失败请切换线路。';
    }
  }

  PlaybackFailure copyWith({
    PlaybackFailureKind? kind,
    String? message,
    int? attempt,
    int? maxAttempts,
    String? rawError,
  }) =>
      PlaybackFailure(
        kind: kind ?? this.kind,
        message: message ?? this.message,
        attempt: attempt ?? this.attempt,
        maxAttempts: maxAttempts ?? this.maxAttempts,
        rawError: rawError ?? this.rawError,
      );

  /// 把内核原始报错归类。
  ///
  /// 归类靠关键词匹配而非错误码，原因：media_kit 走 libmpv，
  /// `stream.error` 下发的是**人类可读字符串**（如
  /// `Failed to open https://...` / `HTTP error 403`），
  /// 不同平台与 mpv 版本的措辞还不完全一致。
  /// 因此匹配顺序按"最具体的特征优先"排列，全部落空则归入 [unknown]。
  factory PlaybackFailure.fromRaw(
    Object error, {
    int attempt = 0,
    int maxAttempts = 0,
    String? url,
  }) {
    final raw = '$error'.trim();
    final lower = raw.toLowerCase();

    PlaybackFailureKind kind;

    if (_matches(lower, '403', 'forbidden', 'access denied', 'unauthorized', '401')) {
      kind = PlaybackFailureKind.forbidden;
    } else if (_matches(lower, '404', 'not found', 'no such file', '410')) {
      kind = PlaybackFailureKind.notFound;
    } else if (_matches(lower, 'timed out', 'timeout', 'connection reset', 'no route')) {
      kind = PlaybackFailureKind.timeout;
    } else if (_matches(lower, 'could not resolve', 'network is unreachable', 'failed to connect')) {
      kind = PlaybackFailureKind.network;
    } else if (_matches(lower, 'unsupported', 'not supported', 'unknown format', 'no video')) {
      kind = PlaybackFailureKind.unsupported;
    } else if (_matches(lower, 'decode', 'decoding', 'hwdec', 'codec')) {
      kind = PlaybackFailureKind.decode;
    } else if (_matches(lower, 'invalid', 'malformed', 'not a playlist')) {
      kind = PlaybackFailureKind.unsupported;
    } else {
      kind = PlaybackFailureKind.unknown;
    }

    // 地址本身不像直链 → 覆盖为"需要解析"，这个判断比报错文本更可靠
    if (url != null && kind == PlaybackFailureKind.unknown) {
      final u = url.toLowerCase();
      final looksDirect = u.startsWith('http') &&
          (u.contains('.m3u8') ||
              u.contains('.mp4') ||
              u.contains('.mkv') ||
              u.contains('.flv') ||
              u.contains('.ts') ||
              u.contains('.mpd'));
      if (!looksDirect) kind = PlaybackFailureKind.parseFailed;
    }

    return PlaybackFailure(
      kind: kind,
      message: raw.isEmpty ? kind.label : raw,
      attempt: attempt,
      maxAttempts: maxAttempts,
      rawError: raw.isEmpty ? null : raw,
    );
  }

  /// 关键词命中：既要匹配数字码，也要匹配文字描述。
  static bool _matches(String haystack, String a, [String? b, String? c, String? d]) {
    for (final needle in <String?>[a, b, c, d]) {
      if (needle != null && needle.isNotEmpty && haystack.contains(needle)) {
        return true;
      }
    }
    return false;
  }

  /// 值相等。同上：`PlaybackState` 的值相等判定需要它，
  /// 否则每次重试都会因为 `PlaybackFailure` 是新实例而触发多余通知。
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaybackFailure &&
          other.kind == kind &&
          other.message == message &&
          other.attempt == attempt &&
          other.maxAttempts == maxAttempts &&
          other.rawError == rawError;

  @override
  int get hashCode =>
      Object.hash(kind, message, attempt, maxAttempts, rawError);

  @override
  String toString() =>
      'PlaybackFailure(${kind.name}, attempt=$attempt/$maxAttempts)';
}

/// 播放器状态快照。
///
/// 这是一个**不可变值对象**，由 `PlayerEngine` 通过
/// `ValueListenable<PlaybackState>` 高频推送（位置更新可达 10Hz）。
///
/// 关键约束：**绝不能让这个对象流经 Riverpod 的全局 state**。
/// 10Hz 的 state 变更会让整棵订阅树每帧重建；UI 侧必须用
/// `ValueListenableBuilder` 把重建范围限定在时间标签与进度条内部。
@immutable
class PlaybackState {
  const PlaybackState({
    this.status = PlaybackStatus.idle,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffered = Duration.zero,
    this.rate = 1.0,
    this.volume = 100,
    this.videoWidth = 0,
    this.videoHeight = 0,
    this.failure,
  });

  /// 初始状态（未加载任何媒体）。
  static const PlaybackState initial = PlaybackState();

  final PlaybackStatus status;

  final Duration position;

  /// 总时长。直播流或尚未解析出时长时为 [Duration.zero]。
  final Duration duration;

  /// 已缓冲到的位置（进度条的浅色预览段）。
  final Duration buffered;

  final double rate;

  /// 音量 0~100（与 mpv 的属性域一致）。
  final double volume;

  final int videoWidth;
  final int videoHeight;

  /// 非空表示处于失败态，UI 应展示错误浮层。
  final PlaybackFailure? failure;

  // ── 派生 ────────────────────────────────────────────────

  bool get isPlaying => status == PlaybackStatus.playing;

  bool get isBuffering => status == PlaybackStatus.buffering;

  bool get hasFailure => failure != null;

  /// 是否已拿到时长。没有时长就没法画进度条，也不该允许拖动。
  bool get isSeekable => duration > Duration.zero;

  /// 播放进度 0.0~1.0。
  double get progress {
    final total = duration.inMilliseconds;
    if (total <= 0) return 0;
    return _clamp01(position.inMilliseconds / total);
  }

  /// 缓冲进度 0.0~1.0。
  double get bufferedProgress {
    final total = duration.inMilliseconds;
    if (total <= 0) return 0;
    return _clamp01(buffered.inMilliseconds / total);
  }

  /// 收敛到 `0.0 ~ 1.0`。
  ///
  /// 显式比较而非 `num.clamp`：后者静态返回 `num`，
  /// 在这些需要 `double` 的位置会多出一次转换。
  static double _clamp01(double value) {
    if (value < 0) return 0;
    if (value > 1) return 1;
    return value;
  }

  /// `01:23:45` / `12:30`
  static String formatDuration(Duration value) {
    final totalSeconds = value.inSeconds;
    if (totalSeconds <= 0) return '00:00';
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
  }

  PlaybackState copyWith({
    PlaybackStatus? status,
    Duration? position,
    Duration? duration,
    Duration? buffered,
    double? rate,
    double? volume,
    int? videoWidth,
    int? videoHeight,
    PlaybackFailure? failure,
    bool clearFailure = false,
  }) =>
      PlaybackState(
        status: status ?? this.status,
        position: position ?? this.position,
        duration: duration ?? this.duration,
        buffered: buffered ?? this.buffered,
        rate: rate ?? this.rate,
        volume: volume ?? this.volume,
        videoWidth: videoWidth ?? this.videoWidth,
        videoHeight: videoHeight ?? this.videoHeight,
        failure: clearFailure ? null : (failure ?? this.failure),
      );

  /// 值相等。
  ///
  /// 为什么需要它：内核通过 `ValueNotifier<PlaybackState>` 推送状态，
  /// 而 `ValueNotifier` 用 `==` 决定是否通知监听者。libmpv 会**重复上报**
  /// 同一个 `buffering=false`、同一个 `volume`，没有值相等判定时
  /// 这些重复事件会白白触发一轮 UI 重建。
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaybackState &&
          other.status == status &&
          other.position == position &&
          other.duration == duration &&
          other.buffered == buffered &&
          other.rate == rate &&
          other.volume == volume &&
          other.videoWidth == videoWidth &&
          other.videoHeight == videoHeight &&
          other.failure == failure;

  @override
  int get hashCode => Object.hash(
        status,
        position,
        duration,
        buffered,
        rate,
        volume,
        videoWidth,
        videoHeight,
        failure,
      );

  @override
  String toString() => 'PlaybackState(${status.label}, '
      '${formatDuration(position)}/${formatDuration(duration)}, x$rate)';
}
