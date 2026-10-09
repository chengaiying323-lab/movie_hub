import 'package:meta/meta.dart';

/// 播放内核运行期配置。
///
/// 为什么要把这些数字集中成一个值对象而不是散落在实现里：
/// 1. **可调**：弱网用户可以把 [stallTimeout] 调大，低配设备可以关硬解；
/// 2. **可测**：测试注入 `maxRetryAttempts: 0` 即可关闭自动重试；
/// 3. **可换内核**：不同内核（libmpv / AVPlayer）共用同一份策略配置，
///    差异只体现在各实现如何把配置落到自己的属性上。
@immutable
class PlayerEngineConfig {
  const PlayerEngineConfig({
    this.maxRetryAttempts = 3,
    this.retryBaseDelay = const Duration(milliseconds: 800),
    this.retryMaxDelay = const Duration(seconds: 8),
    this.openTimeout = const Duration(seconds: 25),
    this.stallTimeout = const Duration(seconds: 20),
    this.hardwareAcceleration = true,
    this.networkTimeoutSec = 20,
    this.demuxerMaxBytes = '64MiB',
    this.demuxerMaxBackBytes = '16MiB',
    this.defaultHeaders = const <String, String>{},
  });

  /// 自动重试上限（不含首次播放）。
  ///
  /// 默认 3 次，配合指数的退避（0.8s → 1.6s → 3.2s）后总等待约 5.6 秒，
  /// 这个量级刚好覆盖「瞬时抖动」又不至于让用户觉得卡死了。
  final int maxRetryAttempts;

  /// 首次重试的等待时长，后续按 2 的幂递增。
  final Duration retryBaseDelay;

  /// 单次重试等待的上限（防止指数爆炸）。
  final Duration retryMaxDelay;

  /// 打开媒体的超时：超过该时长仍未拿到时长/首帧即判定为失败。
  ///
  /// 这是**唯一**能兜住「源站接受了 TCP 连接却一直不发数据」的机制——
  /// 这种情况 libmpv 可能既不报错也不推进，只靠 `stream.error` 会永远卡住。
  final Duration openTimeout;

  /// 播放中的断流判定：位置停止推进超过该时长即视为断流。
  ///
  /// 必须大于 HLS 的分片时长（通常 4~10 秒），否则每次正常切分片都会被误判。
  final Duration stallTimeout;

  /// 是否启用硬件加速解码。
  ///
  /// Windows 上由 libmpv 走 D3D11VA / DXVA2；关闭后回落软解（CPU 占用高但兼容性好）。
  final bool hardwareAcceleration;

  /// 网络读写超时（秒），落到 mpv 的 `network-timeout`。
  final int networkTimeoutSec;

  /// 解复用器前向缓冲上限。弱网环境下适当调大可减少卡顿，
  /// 但会线性增加内存占用。
  ///
  /// 写法必须是 mpv 认的尺寸字符串（`64MiB` / `128MiB`），
  /// 而不是字节数 —— 这是 `-Ddemuxer-max-bytes` 的原生格式。
  final String demuxerMaxBytes;

  /// 解复用器回退缓冲上限（用于 backward seek 的秒回）。
  final String demuxerMaxBackBytes;

  /// 全局默认请求头。
  ///
  /// 优先级最低：**源配置声明的头 > 本字段 > 内核兜底 UA**。
  /// 常见用法是给所有请求统一加一条 `Referer`（有些 CDN 要求）。
  final Map<String, String> defaultHeaders;

  /// 倍速可选档位（用户明确要求的一组）。
  static const List<double> speedOptions = <double>[0.5, 1.0, 1.25, 1.5, 2.0];

  /// 双击快进/快退的步长。
  static const Duration doubleTapSeekStep = Duration(seconds: 10);

  PlayerEngineConfig copyWith({
    int? maxRetryAttempts,
    Duration? retryBaseDelay,
    Duration? retryMaxDelay,
    Duration? openTimeout,
    Duration? stallTimeout,
    bool? hardwareAcceleration,
    int? networkTimeoutSec,
    String? demuxerMaxBytes,
    String? demuxerMaxBackBytes,
    Map<String, String>? defaultHeaders,
  }) =>
      PlayerEngineConfig(
        maxRetryAttempts: maxRetryAttempts ?? this.maxRetryAttempts,
        retryBaseDelay: retryBaseDelay ?? this.retryBaseDelay,
        retryMaxDelay: retryMaxDelay ?? this.retryMaxDelay,
        openTimeout: openTimeout ?? this.openTimeout,
        stallTimeout: stallTimeout ?? this.stallTimeout,
        hardwareAcceleration: hardwareAcceleration ?? this.hardwareAcceleration,
        networkTimeoutSec: networkTimeoutSec ?? this.networkTimeoutSec,
        demuxerMaxBytes: demuxerMaxBytes ?? this.demuxerMaxBytes,
        demuxerMaxBackBytes: demuxerMaxBackBytes ?? this.demuxerMaxBackBytes,
        defaultHeaders: defaultHeaders ?? this.defaultHeaders,
      );

  @override
  String toString() => 'PlayerEngineConfig(hwdec=$hardwareAcceleration, '
      'retry=$maxRetryAttempts, stall=${stallTimeout.inSeconds}s)';
}
