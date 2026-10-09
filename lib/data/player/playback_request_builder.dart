import 'package:meta/meta.dart';

import '../../core/constants/app_constants.dart';
import '../../core/player/playback_source.dart';
import '../../domain/entities/episode.dart';
import '../../domain/entities/movie.dart';
import '../../domain/entities/play_source.dart';
import '../../domain/entities/source_config.dart';

/// 领域实体 → 播放请求的翻译层。
///
/// 为什么需要这一层（而不是让播放页直接拼 `PlaybackSource`）
/// ------------------------------------------------------------------
/// 1. **解耦**：`core/player` 不认识 `Movie` / `Episode` / `SourceConfig`。
///    如果让内核直接吃领域实体，那"换内核"就得连领域模型一起改。
/// 2. **单一职责**：防盗链请求头的推导规则（UA / Referer / Origin / Cookie
///    的优先级与兜底）是**数据层知识**——它取决于数据源协议怎么描述站点，
///    与"怎么播放"无关。
/// 3. **可测**：这是一个纯函数，输入实体、输出请求，单测不需要起播放器。
///
/// 防盗链的现实
/// ------------------------------------------------------------------
/// 影视聚合场景里，直链几乎从不裸奔。常见的三类校验：
/// * **Referer 白名单**：CDN 只放行来自本站页面的请求 → 需要伪造 `Referer`；
/// * **UA 校验**：拒绝空 UA 与明显的命令行 UA → 需要伪装浏览器；
/// * **鉴权 Cookie / 签名参数**：源站登录态或 `?auth=xxx` 时效签名
///   → 需要透传 `Cookie`。
///
/// 本函数按 `源声明 > 协议扩展 > 站点推导 > 全局兜底` 的优先级组装这四类头。
@immutable
class PlaybackRequest {
  const PlaybackRequest({
    required this.source,
    required this.headers,
    required this.episodeIndex,
    required this.isLive,
  });

  final PlaybackSource source;

  /// 最终下发的请求头（已含兜底 UA）。
  final Map<String, String> headers;

  final int episodeIndex;

  final bool isLive;

  /// 诊断用：说明每个关键头是从哪来的。
  ///
  /// 防盗链排查最难的地方是"不知道这个头到底有没有加上"。
  /// 把来源显式记下来，问题反馈时可以直接贴出来。
  String describeHeaderOrigin() {
    final referer = headers['Referer'] ?? headers['referer'] ?? '';
    final ua = headers['User-Agent'] ?? headers['user-agent'] ?? '';
    final cookie = headers['Cookie'] ?? headers['cookie'] ?? '';
    return 'Referer=${referer.isEmpty ? '(无)' : referer} · '
        'UA=${ua.isEmpty ? '(无)' : '${ua.substring(0, ua.length > 24 ? 24 : ua.length)}…'} · '
        'Cookie=${cookie.isEmpty ? '(无)' : '已注入'}';
  }
}

/// 构造播放请求（纯函数，无副作用）。
///
/// [startPositionMs] 由调用方从 `WatchRecord.lastPositionMs` 传入；
/// 传 0 表示从头播放。注意这里只是**携带**它，
/// 真正的 Seek 由内核在拿到时长后执行（见 [PlaybackSource.startPositionMs]）。
PlaybackRequest buildPlaybackRequest({
  required Movie movie,
  required PlaySource source,
  required Episode episode,
  SourceConfig? config,
  int startPositionMs = 0,
  bool? isLive,
}) {
  final url = episode.url.trim();
  final headers = buildPlaybackHeaders(url: url, config: config);
  final live = isLive ?? _looksLive(source: source, episode: episode, config: config);

  return PlaybackRequest(
    source: PlaybackSource(
      url: url,
      title: _composeTitle(movie: movie, source: source, episode: episode),
      headers: headers,
      startPositionMs: startPositionMs < 0 ? 0 : startPositionMs,
      isLive: live,
    ),
    headers: headers,
    episodeIndex: episode.index,
    isLive: live,
  );
}

/// 单独暴露请求头组装，便于设置页预览"当前生效的请求头"。
///
/// 优先级（后者覆盖前者）：
/// 1. 由 [url] 推导的 `Referer` / `Origin`（用播放地址自身的站点）；
/// 2. `SourceConfig.api` 的站点 origin 兜底 Referer；
/// 3. `SourceConfig.extra` 的协议扩展（`headers` / `cookie` / `referer`）；
/// 4. `SourceConfig.headers` 的源站声明（最高优先级）；
/// 5. 缺失 `User-Agent` 时补 [AppConstants.defaultUserAgent]。
Map<String, String> buildPlaybackHeaders({
  required String url,
  SourceConfig? config,
}) {
  final headers = <String, String>{};

  // ── 1 & 2. Referer / Origin 推导 ─────────────────────
  // 优先用数据源声明；没有就用源站 API 的 origin。
  // 直接用播放地址自身的 origin 通常无效（防盗链校验的是"页面来源"，
  // 而不是"资源所在的域"），所以只作为最后兜底。
  final declaredReferer = _extraString(config, 'referer') ??
      _headerOf(config?.headers, 'referer') ??
      '';
  final apiOrigin = _originOf(config?.api ?? '');
  final referer = declaredReferer.isNotEmpty
      ? declaredReferer
      : (apiOrigin.isNotEmpty ? apiOrigin : _originOf(url));
  if (referer.isNotEmpty) headers['Referer'] = referer;

  final originOfReferer = _originOf(referer, keepPath: false);
  if (originOfReferer.isNotEmpty) headers['Origin'] = originOfReferer;

  // ── 3. 协议扩展位 ────────────────────────────────────
  final extraHeaders = config?.extra['headers'];
  if (extraHeaders is Map) {
    extraHeaders.forEach((key, value) {
      final k = '$key'.trim();
      final v = '$value'.trim();
      if (k.isNotEmpty && v.isNotEmpty) headers[k] = v;
    });
  }

  final extraCookie = _extraString(config, 'cookie');
  if (extraCookie != null && extraCookie.isNotEmpty) {
    headers['Cookie'] = extraCookie;
  }

  // ── 4. 源站声明的头（最高优先级，覆盖上面所有推导值） ──
  config?.headers.forEach((key, value) {
    final k = key.trim();
    final v = value.trim();
    if (k.isEmpty) return;
    // 同名头以声明值为准，但大小写可能不同 → 先清掉旧的
    headers.removeWhere((existing, _) => existing.toLowerCase() == k.toLowerCase());
    if (v.isNotEmpty) headers[k] = v;
  });

  // ── 5. 兜底 UA ───────────────────────────────────────
  final hasUserAgent =
      headers.keys.any((key) => key.toLowerCase() == 'user-agent');
  if (!hasUserAgent) {
    headers['User-Agent'] = AppConstants.defaultUserAgent;
  }

  return headers;
}

// ── 内部工具 ──────────────────────────────────────────────

/// 标题：`影片名 · 第 3 集`；单集影片不拼集名，避免出现「影片名 · 正片」。
String _composeTitle({
  required Movie movie,
  required PlaySource source,
  required Episode episode,
}) {
  final episodeName = episode.name.trim();
  if (source.episodeCount <= 1 || episodeName.isEmpty) return movie.title;
  if (episodeName == movie.title) return movie.title;
  return '${movie.title} · $episodeName';
}

/// 直播判定。
///
/// 三条依据按可靠性排序：显式配置 > 线路标志 > 集名特征。
/// 刻意**不看 URL**：大量点播源把地址写在 `.../live/xxx.m3u8` 目录下，
/// 按路径猜直播会误伤，而误判的代价是"进度条消失、进度不保存"。
bool _looksLive({
  required PlaySource source,
  required Episode episode,
  SourceConfig? config,
}) {
  final declared = config?.extra['live'];
  if (declared is bool) return declared;

  final haystack = '${source.flag} ${source.name} ${episode.flag ?? ''}'
      .toLowerCase();
  return haystack.contains('live') || haystack.contains('直播');
}

String? _extraString(SourceConfig? config, String key) {
  final value = config?.extra[key];
  if (value is String && value.trim().isNotEmpty) return value.trim();
  return null;
}

/// 大小写不敏感地读取某个头。
String? _headerOf(Map<String, String>? headers, String name) {
  if (headers == null) return null;
  final target = name.toLowerCase();
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == target && entry.value.trim().isNotEmpty) {
      return entry.value.trim();
    }
  }
  return null;
}

/// 取 URL 的 origin 或 origin + 路径。
///
/// [keepPath] 为 true 时返回带路径的形态（用于 Referer，部分源站要求
/// 完整页面地址）；为 false 时只返回 `scheme://host[:port]`（用于 Origin，
/// 按 CORS 规范 Origin 不带路径与末尾斜杠）。
String _originOf(String url, {bool keepPath = true}) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return '';
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return '';

  final base = '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
  if (!keepPath) return base;
  if (uri.path.isEmpty || uri.path == '/') return '$base/';
  return '$base${uri.path}';
}
