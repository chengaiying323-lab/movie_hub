import 'dart:convert';

import 'package:crypto/crypto.dart';

/// 全局唯一 ID 生成器。
///
/// 影视条目在"跨源"维度上并不天然唯一：`vod_id` 仅在单个源站内唯一。
/// 因此全局 ID 采用 `{sourceKey}:{vodId}` 组合键；对需要定长 ID 的场景
/// （如播放器会话、缓存文件名）提供 md5 摘要变体。
class IdGenerator {
  const IdGenerator._();

  /// 影片全局唯一 ID。
  static String movieId(String sourceKey, Object? vodId) =>
      '$sourceKey:${vodId ?? ''}';

  /// 线路 ID：同一影片下同一线路标志（vod_play_from）唯一。
  static String playSourceId(String movieId, String flag) =>
      '$movieId#$flag';

  /// 定长摘要 ID，用于缓存文件名 / 本地播放记录主键。
  static String hash(String input) =>
      md5.convert(utf8.encode(input)).toString();

  /// 去重键（稳定、可读，便于日志排查）。
  static String dedupeKey(String normalizedTitle, int? year) =>
      year == null ? normalizedTitle : '$normalizedTitle|$year';
}
