import 'package:meta/meta.dart';

/// 媒体容器 / 传输协议类型。
///
/// 为什么需要显式类型而不是"把 URL 丢给播放器就完事"：
/// 1. **可观测**：UI 需要显示「HLS 直播流」这类信息，便于用户判断为什么卡；
/// 2. **可降级**：HLS 与 MP4 的缓冲/重试策略不同（前者是分片流，断流恢复
///    代价低；后者是大文件，重试要从断点续传）；
/// 3. **可诊断**：`unknown` 是重要信号——说明源站给的是需要二次解析的页面地址，
///    播放器必然失败，应当直接提示"换线路"而不是傻等超时。
enum MediaKind {
  hls('hls', 'HLS 流'),
  dash('dash', 'DASH 流'),
  mp4('mp4', 'MP4'),
  mkv('mkv', 'MKV'),
  flv('flv', 'FLV'),
  ts('ts', 'TS 分片'),
  unknown('unknown', '未知格式');

  const MediaKind(this.wire, this.label);

  /// 协议标识（用于日志与诊断展示）。
  final String wire;

  /// 面向用户的短标签。
  final String label;

  /// 从 URL 推导媒体类型。
  ///
  /// 判定顺序很重要：**先看 `?` 之前的路径段**，再看查询串。
  /// 部分源站把类型放在查询参数里（`play.php?type=m3u8&id=1`），
  /// 只匹配路径会全部落到 `unknown`。
  static MediaKind fromUrl(String url) {
    final value = url.trim().toLowerCase();
    if (value.isEmpty) return MediaKind.unknown;

    final withoutQuery = value.split('?').first;

    if (_hasExtension(withoutQuery, 'm3u8') || value.contains('type=m3u8')) {
      return MediaKind.hls;
    }
    if (_hasExtension(withoutQuery, 'mpd')) return MediaKind.dash;
    if (_hasExtension(withoutQuery, 'mp4') ||
        _hasExtension(withoutQuery, 'm4v')) {
      return MediaKind.mp4;
    }
    if (_hasExtension(withoutQuery, 'mkv')) return MediaKind.mkv;
    if (_hasExtension(withoutQuery, 'flv')) return MediaKind.flv;
    if (_hasExtension(withoutQuery, 'ts')) return MediaKind.ts;
    return MediaKind.unknown;
  }

  /// 后缀匹配必须带前导 `.`，否则 `.../tips` 会被误判为 `.ts`。
  static bool _hasExtension(String path, String ext) =>
      path.endsWith('.$ext') || path.contains('.$ext/');
}

/// 播放请求描述（内核可消费的**完整**输入）。
///
/// 设计要点
/// ------------------------------------------------------------------
/// **1. 这是 `core` 层的值对象，不认识 `Movie` / `Episode`。**
/// 由 `data/player/playback_request_builder.dart` 负责把领域实体翻译成它，
/// 从而让播放内核与领域模型解耦：内核可以被任意页面复用，
/// 领域模型改字段也不会波及内核。
///
/// **2. 请求头是"播放"这件事实质的一部分。**
/// 影视聚合场景里，直链通常带防盗链（校验 `Referer` / `Origin`）
/// 或签名鉴权（校验 `Cookie` / `User-Agent`）。
/// 不做请求头注入，绝大多数 m3u8 会直接返回 403。
@immutable
class PlaybackSource {
  const PlaybackSource({
    required this.url,
    required this.title,
    this.headers = const <String, String>{},
    this.startPositionMs = 0,
    this.kind,
    this.isLive = false,
  });

  /// 媒体地址。必须是可直接投喂播放器的直链（m3u8 / mp4 / mkv…）。
  final String url;

  /// 展示用标题（播放页顶部、锁屏信息、错误提示共用）。
  final String title;

  /// 随请求下发的 HTTP 头（UA / Referer / Cookie / Origin…）。
  ///
  /// 空 Map 表示"用内核全局默认值"，此时仍会带上兜底 UA。
  final Map<String, String> headers;

  /// 起播位置（毫秒）。0 表示从头播放。
  ///
  /// 实现层不应把它写进 `Player.open` 的参数里，而应在拿到时长后
  /// 执行一次 Seek —— 多数内核在 `open` 完成前 Seek 会被丢弃。
  final int startPositionMs;

  /// 显式指定的媒体类型；为 null 时由 [effectiveKind] 从 URL 推导。
  final MediaKind? kind;

  /// 是否为直播流（无总时长、不可 Seek）。
  ///
  /// 直播与点播的 UI 差异很大：直播不显示进度条、不显示剩余时间、
  /// 不允许快进，也不应回写播放进度。
  final bool isLive;

  MediaKind get effectiveKind => kind ?? MediaKind.fromUrl(url);

  /// 是否可以回写/恢复播放进度。直播流与未知格式都不该写进度。
  bool get isSeekable => !isLive && effectiveKind != MediaKind.unknown;

  /// 主机名（用于诊断展示，如「example.com」）。
  String get host {
    final uri = Uri.tryParse(url);
    return uri?.host ?? '';
  }

  PlaybackSource copyWith({
    String? url,
    String? title,
    Map<String, String>? headers,
    int? startPositionMs,
    MediaKind? kind,
    bool? isLive,
  }) =>
      PlaybackSource(
        url: url ?? this.url,
        title: title ?? this.title,
        headers: headers ?? this.headers,
        startPositionMs: startPositionMs ?? this.startPositionMs,
        kind: kind ?? this.kind,
        isLive: isLive ?? this.isLive,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaybackSource &&
          other.url == url &&
          other.startPositionMs == startPositionMs;

  @override
  int get hashCode => Object.hash(url, startPositionMs);

  @override
  String toString() =>
      'PlaybackSource(${effectiveKind.wire}, $host, '
      'headers=${headers.length}, seek=${startPositionMs}ms)';
}
