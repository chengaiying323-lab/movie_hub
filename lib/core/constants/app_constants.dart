/// 全局常量集中定义。
///
/// 原则：任何"魔法字符串/数字"都必须在此处具名，禁止散落在业务代码中，
/// 以便后续协议升级与平台差异化配置只需改动一处。
class AppConstants {
  const AppConstants._();

  // ── 应用元信息 ─────────────────────────────────────────
  static const String appName = 'MovieHub';
  static const String appVersion = '1.0.0';

  /// 客户端支持的数据源订阅协议版本。
  /// 订阅包声明 [protocolVersion] 高于此值时，客户端应拒绝导入并提示升级。
  static const String protocolVersion = 'moviehub/v1';

  /// 兼容的外部生态协议标识（TVBox / 苹果CMS 站点订阅）。
  static const String tvboxProtocolVersion = 'tvbox/1';

  // ── 网络默认参数 ───────────────────────────────────────
  /// 部分 CMS 站点有反爬 UA 校验，必须伪装为常见桌面浏览器。
  static const String defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36';

  static const Map<String, String> defaultHeaders = <String, String>{
    'User-Agent': defaultUserAgent,
    'Accept': 'application/json, text/plain, */*',
  };

  static const Duration connectTimeout = Duration(seconds: 8);
  static const Duration receiveTimeout = Duration(seconds: 12);

  /// 单源搜索超时。聚合搜索时取"最短超时"原则，避免单个慢源拖垮整体体验。
  static const Duration sourceSearchTimeout = Duration(seconds: 8);

  /// 多源并发上限。移动端内存与弱网环境下不宜过大。
  static const int maxConcurrentSources = 10;

  static const int maxRetryAttempts = 1;

  // ── 苹果CMS / TVBox 播放串分隔符（协议默认值） ───────────
  /// 线路之间的分隔符：`线路A$$$线路B`
  static const String defaultSourceSeparator = r'$$$';

  /// 线路内剧集之间的分隔符：`第1集$url#第2集$url`
  static const String defaultEpisodeSeparator = '#';

  /// 剧集名与播放地址之间的分隔符：`第1集$http://...`
  static const String defaultEpisodeNameSeparator = r'$';

  // ── 本地持久化键名 ─────────────────────────────────────
  static const String kSourcesKey = 'movie_hub.sources.v1';
  static const String kSubscriptionsKey = 'movie_hub.subscriptions.v1';
  static const String kSearchHistoryKey = 'movie_hub.search_history.v1';
  static const int kSearchHistoryLimit = 20;

  // ── 观看记录（Hive） ──────────────────────────────────
  /// Hive box 名。Box 以 `WatchRecord.id` 为键，实现 O(1) 命中与 upsert。
  static const String kWatchRecordBox = 'movie_hub_watch_records';

  /// 旧版（SharedPreferences）键名，仅用于一次性数据迁移。
  static const String kLegacyProgressKey = 'movie_hub.watch_progress.v1';
  static const String kLegacyFavoritesKey = 'movie_hub.favorites.v1';

  /// 迁移完成标记键（写在 SharedPreferences，避免重复迁移）。
  static const String kWatchMigrationDoneKey = 'movie_hub.watch_migrated.v1';

  /// 观看记录条数上限。超出时按 `updatedAt` 淘汰最旧的非「想看」条目。
  static const int kMaxWatchRecords = 500;

  // ── 播放进度回写策略 ──────────────────────────────────
  /// 播放期间的回写周期：每 5 秒落盘一次。
  ///
  /// 为什么不逐帧写？播放器位置回调频率可达 1~10 Hz，
  /// 每次落盘都会带来磁盘 IO 与 State 重建；5 秒是
  /// 「进度不丢太多」与「写入不过于频繁」的平衡点。
  /// 暂停 / 切集 / 退出时会立即补一次 [flush]，因此不会丢失末段进度。
  static const Duration kProgressFlushInterval = Duration(seconds: 5);

  /// 进度变化小于该值则跳过本次落盘（避免暂停时的重复写入）。
  static const int kProgressMinDeltaMs = 2000;

  /// 播放进度超过该比例即自动标记为「已看」。
  static const double kWatchedThreshold = 0.90;

  /// 低于该比例视为"刚点开就退出"，不进入「继续观看」。
  static const double kResumeMinPercent = 0.01;

  /// 「继续观看」条目在首页最多展示数量。
  static const int kResumeListLimit = 12;

  // ── 校验探针 ───────────────────────────────────────────
  /// 数据源可用性校验使用的探针关键词。
  static const String healthProbeKeyword = '测试';

  /// 校验时要求的最小有效结果数，低于该值判定为 degraded。
  static const int healthMinSample = 1;
}
