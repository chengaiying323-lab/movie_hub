import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/design.dart';
import '../../domain/entities/home_feed.dart';
import '../../domain/entities/movie.dart';
import '../../domain/entities/watch_record.dart';
import '../app_navigation.dart';
import '../providers/home_providers.dart';
import '../providers/watch_history_providers.dart';
import '../widgets/adaptive_scaffold.dart';
import '../widgets/app_menu.dart';
import '../widgets/continue_watching_row.dart';
import '../widgets/empty_state.dart';
import '../widgets/hero_banner.dart';
import '../widgets/movie_row.dart';
import '../widgets/shimmer.dart';
import '../widgets/watch_status_button.dart';

/// 首页（发现）。
///
/// 页面结构（自上而下）
/// ------------------------------------------------------------------
/// 1. 顶部浅色半透明渐变焦点图（[HeroBanner]）；
/// 2. 「继续观看」进度浮层（仅当有观看记录时出现）；
/// 3. 若干「热门推荐」横向滑动栏。
///
/// 性能策略：首屏只加载前 3 个分区（见 `HomeFeedNotifier`），
/// 剩余分区在滚动接近底部时补齐，避免一次性发起 4 个分类请求。
class DiscoverPage extends ConsumerStatefulWidget {
  const DiscoverPage({
    super.key,
    required this.onOpenSearch,
    required this.onOpenSources,
  });

  final void Function(String keyword) onOpenSearch;
  final VoidCallback onOpenSources;

  @override
  ConsumerState<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends ConsumerState<DiscoverPage> {
  final ScrollController _scrollController = ScrollController();
  bool _requestedRest = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_requestedRest) return;
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    // 距底部 600px 时预加载剩余分区
    if (position.pixels >= position.maxScrollExtent - 600) {
      _requestedRest = true;
      ref.read(homeFeedProvider.notifier).loadRest();
    }
  }

  void _openMovie(Movie movie) => AppRoutes.openDetail(
        context,
        sourceKey: movie.sourceKey,
        vodId: movie.vodId,
        seed: movie,
      );

  /// 续播：把线路与集数一起带进详情页，由详情页自动定位。
  ///
  /// 同时把记录投影为 [Movie] 作为 seed：详情页可以先渲染标题与海报，
  /// 不必等接口返回，点「继续观看」的响应会明显更快。
  void _resume(WatchRecord record) => AppRoutes.openDetail(
        context,
        sourceKey: record.sourceKey,
        vodId: record.vodId,
        seed: _asMovie(record),
        resumeSourceFlag:
            record.playSourceFlag.isEmpty ? null : record.playSourceFlag,
        resumeEpisodeIndex: record.currentEpisodeIndex,
      );

  /// 把观看记录投影为 [Movie]（只填列表展示需要的字段）。
  static Movie _asMovie(WatchRecord record) => Movie(
        id: record.movieId,
        vodId: record.vodId,
        sourceKey: record.sourceKey,
        sourceName: record.sourceName,
        title: record.title,
        poster: record.posterUrl,
        year: record.year,
        remarks: record.remarks,
      );

  /// 打开详情（不带续播定位）。
  void _openDetail(WatchRecord record) => AppRoutes.openDetail(
        context,
        sourceKey: record.sourceKey,
        vodId: record.vodId,
        seed: _asMovie(record),
      );

  @override
  Widget build(BuildContext context) {
    final feedState = ref.watch(homeFeedProvider);
    final resumeList = ref.watch(resumeListProvider);
    final layout = AppLayout.of(context);
    final bottomInset = AppScaffoldInsets.bottomOf(context);

    return RefreshIndicator(
      // 移动端下拉刷新；桌面端由头部按钮触发
      onRefresh: () => ref.read(homeFeedProvider.notifier).reload(),
      color: AppColors.accent,
      backgroundColor: AppColors.surface,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: _Header(
              onOpenSearch: widget.onOpenSearch,
              onRefresh: () => ref.read(homeFeedProvider.notifier).reload(),
            ),
          ),

          ...feedState.when(
            loading: () => <Widget>[
              const SliverToBoxAdapter(child: _BannerSkeleton()),
              SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
              const SliverToBoxAdapter(child: _RowSkeleton()),
              SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
              const SliverToBoxAdapter(child: _RowSkeleton()),
            ],
            error: (error, _) => <Widget>[
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: layout.pagePadding,
                    vertical: AppSpacing.xxl,
                  ),
                  child: ErrorView(
                    message: '$error',
                    onRetry: () =>
                        ref.read(homeFeedProvider.notifier).reload(),
                  ),
                ),
              ),
            ],
            data: (feed) => _buildContent(feed, resumeList, layout),
          ),

          SliverToBoxAdapter(
            child: SizedBox(height: bottomInset + AppSpacing.xl),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildContent(
    HomeFeed feed,
    List<WatchRecord> resumeList,
    AppLayoutData layout,
  ) {
    if (feed.hasNoSource) {
      return <Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: layout.pagePadding,
              vertical: AppSpacing.xxl,
            ),
            child: EmptyState(
              icon: Icons.dns_outlined,
              title: '还没有可用的数据源',
              description:
                  'MovieHub 不内置任何站点。\n请先导入一份订阅包（JSON），首页内容才会出现。',
              action: OutlinedButton.icon(
                onPressed: widget.onOpenSources,
                icon: const Icon(Icons.add_link, size: 16),
                label: const Text('去导入订阅'),
              ),
            ),
          ),
        ),
      ];
    }

    return <Widget>[
      // 焦点图
      if (feed.banners.isNotEmpty)
        SliverToBoxAdapter(
          child: HeroBanner(
            movies: feed.banners,
            onTap: _openMovie,
            onPlay: _openMovie,
          ),
        ),
      SliverToBoxAdapter(child: SizedBox(height: layout.isLargeScreen ? 28 : 20)),

      // 继续观看
      if (resumeList.isNotEmpty) ...<Widget>[
        SliverToBoxAdapter(
          child: ContinueWatchingRow(
            items: resumeList,
            onResume: _resume,
            onOpenDetail: _openDetail,
            onRemove: (record) async {
              final messenger = ScaffoldMessenger.of(context);
              await ref.read(watchHistoryProvider.notifier).remove(record.id);
              messenger.showSnackBar(
                SnackBar(content: Text('已移除「${record.title}」的观看记录')),
              );
            },
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(height: layout.isLargeScreen ? 28 : 20),
        ),
      ],

      // 推荐分区
      for (final section in feed.sections) ...<Widget>[
        SliverToBoxAdapter(
          child: MovieRow(
            key: ValueKey<String>('section_${section.id}'),
            title: section.title,
            subtitle: section.subtitle,
            movies: section.movies,
            sourceBadgeBuilder: (movie) => movie.sourceName,
            menuActionsBuilder: _menuActions,
            onMenuSelected: _handleMenu,
            onTap: _openMovie,
            onPlay: _openMovie,
            onShowAll: () => widget.onOpenSearch(section.title),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(height: layout.isLargeScreen ? 28 : 20),
        ),
      ],
    ];
  }

  /// 卡片右键 / 长按菜单。
  ///
  /// 状态相关项与详情页的 [WatchStatusButton] 保持同一套语义：
  /// 当前状态对应的那一项置灰，避免"点了却没有变化"的困惑。
  /// 用 `ref.read` 而非 `watch`：菜单是按下时才构建的，
  /// 此处只需要"此刻"的状态快照。
  List<AppMenuAction> _menuActions(Movie movie) {
    final status = ref.read(watchStatusProvider(movie.id));
    return <AppMenuAction>[
      const AppMenuAction(
        value: 'detail',
        label: '查看详情',
        icon: Icons.info_outline_rounded,
      ),
      if (status == WatchStatus.wantToWatch)
        const AppMenuAction(
          value: 'unwant',
          label: '移出「想看」',
          icon: Icons.bookmark_remove_outlined,
        )
      else
        const AppMenuAction(
          value: 'want',
          label: '标记为想看',
          icon: Icons.bookmark_add_outlined,
        ),
      AppMenuAction(
        value: 'watching',
        label: '标记为正在看',
        icon: Icons.play_circle_outline_rounded,
        enabled: status != WatchStatus.watching,
      ),
      AppMenuAction(
        value: 'watched',
        label: '标记为已看',
        icon: Icons.task_alt_rounded,
        enabled: status != WatchStatus.watched,
      ),
      const AppMenuAction(
        value: 'search',
        label: '搜索同名影片',
        icon: Icons.search_rounded,
      ),
    ];
  }

  Future<void> _handleMenu(Movie movie, String value) async {
    final notifier = ref.read(watchHistoryProvider.notifier);

    switch (value) {
      case 'detail':
        _openMovie(movie);
      case 'search':
        widget.onOpenSearch(movie.title);
      case 'want':
        await runWatchAction(
          context,
          action: () => notifier.setStatus(movie, WatchStatus.wantToWatch),
          successMessage: '已将「${movie.title}」标记为想看',
        );
      case 'unwant':
        await runWatchAction(
          context,
          action: () => notifier.remove(movie.id),
          successMessage: '已将「${movie.title}」移出想看',
        );
      case 'watching':
        await runWatchAction(
          context,
          action: () => notifier.setStatus(movie, WatchStatus.watching),
          successMessage: '已将「${movie.title}」标记为正在看',
        );
      case 'watched':
        await runWatchAction(
          context,
          action: () => notifier.setStatus(movie, WatchStatus.watched),
          successMessage: '已将「${movie.title}」标记为已看',
        );
    }
  }
}

// ── 顶部区域 ────────────────────────────────────────────────

class _Header extends StatefulWidget {
  const _Header({
    required this.onOpenSearch,
    required this.onRefresh,
  });

  final void Function(String keyword) onOpenSearch;
  final VoidCallback onRefresh;

  @override
  State<_Header> createState() => _HeaderState();
}

class _HeaderState extends State<_Header> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      widget.onRefresh();
    } finally {
      // 给用户一个可感知的完成反馈
      await Future<void>.delayed(AppMotion.slow);
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = AppLayout.of(context);
    final topSafe = MediaQuery.paddingOf(context).top;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        layout.pagePadding,
        (layout.isDesktop ? AppSpacing.md : topSafe + AppSpacing.sm),
        layout.pagePadding,
        AppSpacing.sm,
      ),
      child: layout.isDesktop
          ? _buildDesktop(context)
          : _buildMobile(context),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return Row(
      children: <Widget>[
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('发现', style: AppTypography.headlineSmall),
            SizedBox(height: 2),
            Text(
              '多源聚合 · 一搜即得',
              style: TextStyle(fontSize: 12.5, color: AppColors.inkTertiary),
            ),
          ],
        ),
        const Spacer(),
        SizedBox(
          width: 320,
          child: _SearchEntry(onTap: () => widget.onOpenSearch('')),
        ),
        const SizedBox(width: AppSpacing.sm),
        _RefreshButton(spinning: _refreshing, onTap: _refresh),
      ],
    );
  }

  Widget _buildMobile(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              child: const Icon(
                Icons.movie_filter_rounded,
                size: 16,
                color: AppColors.inkOnDark,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            const Text(
              'MovieHub',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                color: AppColors.ink,
              ),
            ),
            const Spacer(),
            _RefreshButton(spinning: _refreshing, onTap: _refresh),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _SearchEntry(onTap: () => widget.onOpenSearch('')),
      ],
    );
  }
}

/// 只读搜索入口（点击后跳转到搜索页），外观与 [SearchCapsule] 一致。
class _SearchEntry extends StatefulWidget {
  const _SearchEntry({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_SearchEntry> createState() => _SearchEntryState();
}

class _SearchEntryState extends State<_SearchEntry> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.standard,
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadius.pillBR,
            border: Border.all(
              color: _hovered ? AppColors.hairlineStrong : AppColors.hairline,
              width: AppStroke.hairline,
            ),
            boxShadow: _hovered ? AppShadows.cardHover : AppShadows.card,
          ),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.search_rounded,
                size: 19,
                color: _hovered ? AppColors.accent : AppColors.inkTertiary,
              ),
              const SizedBox(width: AppSpacing.xs),
              const Expanded(
                child: Text(
                  '搜索影片、演员或导演',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: AppColors.inkTertiary),
                ),
              ),
              if (AppLayout.of(context).isDesktop)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: AppRadius.xsBR,
                  ),
                  child: const Text(
                    'Ctrl K',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.inkTertiary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RefreshButton extends StatefulWidget {
  const _RefreshButton({required this.spinning, required this.onTap});

  final bool spinning;
  final VoidCallback onTap;

  @override
  State<_RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends State<_RefreshButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: '刷新推荐',
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: AppMotion.fast,
            width: AppSizes.touchTarget,
            height: AppSizes.touchTarget,
            decoration: BoxDecoration(
              color: _hovered ? AppColors.accentSofter : Colors.transparent,
              borderRadius: AppRadius.smBR,
            ),
            child: AnimatedRotation(
              turns: widget.spinning ? 1 : 0,
              duration: AppMotion.slow,
              curve: AppMotion.standard,
              child: const Icon(
                Icons.refresh_rounded,
                size: 19,
                color: AppColors.inkSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── 骨架 ────────────────────────────────────────────────────

class _BannerSkeleton extends StatelessWidget {
  const _BannerSkeleton();

  @override
  Widget build(BuildContext context) {
    final layout = AppLayout.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: layout.pagePadding),
      child: Shimmer(
        child: Container(
          height: layout.isLargeScreen
              ? AppSizes.bannerHeightDesktop
              : AppSizes.bannerHeightMobile,
          decoration: const BoxDecoration(
            color: AppColors.skeletonBase,
            borderRadius: AppRadius.panelBR,
          ),
        ),
      ),
    );
  }
}

class _RowSkeleton extends StatelessWidget {
  const _RowSkeleton();

  @override
  Widget build(BuildContext context) {
    final layout = AppLayout.of(context);
    final padding = layout.pagePadding;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final railWidth = layout.isDesktop ? AppSizes.railWidth : 0.0;
    final visible = layout.rowVisibleCount;
    final itemWidth = ((screenWidth -
                railWidth -
                padding * 2 -
                AppSpacing.sm * (visible - 1)) /
            visible)
        .clamp(128.0, 208.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.symmetric(horizontal: padding),
          child: const Shimmer(
            child: SkeletonBox(width: 120, height: 16),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: itemWidth / AppSizes.posterAspectRatio + AppSizes.rowTextExtent,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: padding),
            physics: const NeverScrollableScrollPhysics(),
            itemCount: visible + 1,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (_, __) => SizedBox(
              width: itemWidth,
              child: const PosterSkeleton(),
            ),
          ),
        ),
      ],
    );
  }
}
