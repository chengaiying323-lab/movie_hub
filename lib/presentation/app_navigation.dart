import 'package:flutter/material.dart';

import '../core/design/design.dart';
import '../domain/entities/movie.dart';
import 'pages/movie_detail_page.dart';
import 'pages/player_page.dart';

/// 全局路由助手。
///
/// 集中管理页面跳转，避免各页面里散落 `Navigator.push(MaterialPageRoute(...))`：
/// 统一使用 [AppTransition.fadeThrough] 的淡入上移过渡（比平台默认更克制），
/// 也方便后续替换为声明式路由（go_router）时只改这一处。
class AppRoutes {
  const AppRoutes._();

  /// 打开影视详情页。
  ///
  /// [seed] 为列表页已持有的轻量条目——若其已含线路数据，
  /// 详情页将跳过网络请求，直接渲染。
  ///
  /// [resumeSourceFlag] / [resumeEpisodeIndex] 用于「继续观看」：
  /// 详情页据此自动定位到上次播放的线路与集数。
  static Future<void> openDetail(
    BuildContext context, {
    required String sourceKey,
    required String vodId,
    Movie? seed,
    String? resumeSourceFlag,
    int? resumeEpisodeIndex,
  }) {
    return Navigator.of(context).push<void>(
      AppTransition.fadeThrough(
        MovieDetailPage(
          sourceKey: sourceKey,
          vodId: vodId,
          seed: seed,
          resumeSourceFlag: resumeSourceFlag,
          resumeEpisodeIndex: resumeEpisodeIndex,
        ),
        name: 'detail/$sourceKey/$vodId',
      ),
    );
  }

  /// 从「聚合条目」打开详情（取合并后的最优元数据作为 seed）。
  static Future<void> openAggregated(
    BuildContext context, {
    required Movie primary,
    required Movie merged,
  }) {
    return openDetail(
      context,
      sourceKey: primary.sourceKey,
      vodId: primary.vodId,
      seed: merged.sources.isEmpty ? primary : merged,
    );
  }

  /// 打开内嵌播放页。
  ///
  /// 前置条件：[movie] **必须携带 `sources`**（播放页据此提供选集与换线路）。
  /// 因此续播入口（首页「继续观看」、资料库卡片）的路线是
  /// 「续播 → 详情页（补齐线路）→ 播放页」，而不是直接从记录跳播放页
  /// —— 观看记录里只有一条 URL，没有同影片的其它线路与其余选集。
  ///
  /// 续播询问（"上次观看到 12:34，是否继续播放"）由**播放页**发起，
  /// 不在本方法内做：只有播放页知道内核何时真正就绪、能否 Seek。
  static Future<void> openPlayer(
    BuildContext context, {
    required Movie movie,
    required String sourceFlag,
    int episodeIndex = 0,
    bool autoPlay = true,
  }) {
    return Navigator.of(context).push<void>(
      AppTransition.fadeThrough(
        PlayerPage(
          movie: movie,
          sourceFlag: sourceFlag,
          episodeIndex: episodeIndex,
          autoPlay: autoPlay,
        ),
        name: 'player/${movie.sourceKey}/${movie.vodId}',
      ),
    );
  }
}
