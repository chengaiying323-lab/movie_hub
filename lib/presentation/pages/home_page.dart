import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/design.dart';
import '../providers/search_providers.dart';
import '../providers/source_providers.dart';
import '../providers/watch_history_providers.dart';
import '../widgets/adaptive_scaffold.dart';
import 'discover_page.dart';
import 'library_page.dart';
import 'search_page.dart';
import 'source_manage_page.dart';

/// 应用主框架。
///
/// 职责边界：只负责「自适应导航形态 + 页面切换 + 跨页跳转协调」，
/// 不承载任何业务逻辑。
///
/// 使用 [IndexedStack] 而非按需构建：四个页面常驻，
/// 切换 Tab 时保留各自的滚动位置与搜索状态（Tab 型应用的体验基线）。
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  static const int _discoverIndex = 0;
  static const int _searchIndex = 1;
  static const int _sourcesIndex = 3;

  int _index = _discoverIndex;

  void _select(int index) {
    if (index == _index) return;
    setState(() => _index = index);
  }

  /// 从首页/追剧页跳转到搜索页并立即发起搜索。
  void _openSearch(String keyword) {
    final trimmed = keyword.trim();
    if (trimmed.isNotEmpty) {
      ref.read(searchQueryProvider.notifier).state = trimmed;
      // 不 await：切页与搜索并行，用户立刻看到搜索页与骨架屏
      ref.read(searchResultProvider.notifier).search(trimmed);
    }
    _select(_searchIndex);
  }

  void _openSources() => _select(_sourcesIndex);

  @override
  Widget build(BuildContext context) {
    final layout = AppLayout.of(context);
    // 角标只统计「正在看 + 想看」：已看条目会不断累积，
    // 若计入则数字只增不减，很快失去"待处理事项"的提示意义。
    final activeCount = ref.watch(watchActiveCountProvider);
    final enabledSources = ref.watch(enabledSourceCountProvider);

    final destinations = <AppDestination>[
      const AppDestination(
        icon: Icons.explore_outlined,
        selectedIcon: Icons.explore,
        label: '发现',
      ),
      const AppDestination(
        icon: Icons.search_outlined,
        selectedIcon: Icons.search,
        label: '搜索',
      ),
      AppDestination(
        icon: Icons.bookmark_border_rounded,
        selectedIcon: Icons.bookmark_rounded,
        label: '片库',
        badgeCount: activeCount,
      ),
      AppDestination(
        icon: Icons.dns_outlined,
        selectedIcon: Icons.dns_rounded,
        label: '数据源',
        badgeCount: enabledSources,
      ),
    ];

    return AdaptiveScaffold(
      currentIndex: _index,
      onDestinationSelected: _select,
      destinations: destinations,
      brand: _Brand(expanded: layout.isExpandedRail),
      railFooter:
          layout.isExpandedRail ? const _RailFooter() : const SizedBox.shrink(),
      body: IndexedStack(
        index: _index,
        children: <Widget>[
          DiscoverPage(
            onOpenSearch: _openSearch,
            onOpenSources: _openSources,
          ),
          const SearchPage(),
          LibraryPage(onOpenSearch: _openSearch),
          const SourceManagePage(),
        ],
      ),
    );
  }
}

/// 侧边栏品牌区。
class _Brand extends StatelessWidget {
  const _Brand({required this.expanded});

  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final mark = Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        boxShadow: AppShadows.brand,
      ),
      child: const Icon(
        Icons.movie_filter_rounded,
        size: 19,
        color: AppColors.inkOnDark,
      ),
    );

    if (!expanded) return Center(child: mark);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Row(
        children: <Widget>[
          mark,
          const SizedBox(width: AppSpacing.sm),
          const Expanded(
            child: Text(
              'MovieHub',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                color: AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 侧边栏底部：合规提示与版本号。
class _RailFooter extends StatelessWidget {
  const _RailFooter();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Divider(),
          SizedBox(height: AppSpacing.xs),
          Text(
            '数据源由用户自行导入',
            style: TextStyle(fontSize: 10.5, color: AppColors.inkDisabled),
          ),
          SizedBox(height: AppSpacing.xxs),
          Text(
            'v1.0.0',
            style: TextStyle(fontSize: 10.5, color: AppColors.inkDisabled),
          ),
        ],
      ),
    );
  }
}
