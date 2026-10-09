import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/home_feed_service.dart';
import '../../domain/entities/home_feed.dart';
import 'core_providers.dart';

/// 首页聚合数据。
///
/// 加载策略：首屏只取前 3 个分区以尽快出图；剩余分区在
/// [HomeFeedNotifier.loadRest] 中补齐（页面滚动到底部时调用），
/// 避免首屏一次性发起 4 个分类请求拖慢出图时间。
final homeFeedProvider =
    AsyncNotifierProvider<HomeFeedNotifier, HomeFeed>(HomeFeedNotifier.new);

class HomeFeedNotifier extends AsyncNotifier<HomeFeed> {
  /// 首屏分区数量。
  static const int firstScreenSections = 3;

  bool _loadedAll = false;

  @override
  Future<HomeFeed> build() async {
    _loadedAll = false;
    return ref
        .read(homeFeedServiceProvider)
        .load(maxSections: firstScreenSections);
  }

  /// 全量重载（下拉刷新 / 数据源变更后）。
  Future<void> reload() async {
    state = const AsyncValue.loading();
    _loadedAll = false;
    state = await AsyncValue.guard(
      () => ref.read(homeFeedServiceProvider).load(),
    );
    _loadedAll = true;
  }

  /// 补齐剩余分区（仅执行一次）。
  Future<void> loadRest() async {
    if (_loadedAll) return;
    if (state.valueOrNull == null) return;
    if (state.valueOrNull!.sections.length >= HomeFeedService.sections.length) {
      _loadedAll = true;
      return;
    }

    _loadedAll = true;
    final full = await AsyncValue.guard(
      () => ref.read(homeFeedServiceProvider).load(),
    );
    // 补齐失败时保留首屏内容，不回退到错误态
    if (full.hasValue) state = full;
  }
}
