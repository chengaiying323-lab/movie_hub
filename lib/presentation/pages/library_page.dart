import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/design.dart';
import '../../domain/entities/movie.dart';
import '../../domain/entities/watch_record.dart';
import '../app_navigation.dart';
import '../providers/watch_history_providers.dart';
import '../widgets/adaptive_scaffold.dart';
import '../widgets/app_menu.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/empty_state.dart';
import '../widgets/poster_card.dart';
import '../widgets/poster_grid.dart';
import '../widgets/watch_status_button.dart';

/// 资料库页（追剧清单）。
///
/// 结构
/// ------------------------------------------------------------------
/// 顶部标题 + 统计 + 「清空」入口；下方三个分栏 Tab：
/// **正在看 / 想看 / 已看**（顺序即 [WatchStatus.tabOrder]）。
///
/// 每个分栏都是一个独立的 [CustomScrollView]，
/// 因此切换 Tab 时各自的滚动位置会被保留（[TabBarView] 默认行为）。
///
/// 为什么用「列表页 + Tab」而不是三个独立路由？
/// 三者数据同源、切换频繁，独立路由会让"我在哪一栏"变成需要记忆的信息。
class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key, required this.onOpenSearch});

  /// 空态时跳转到搜索页的回调。
  final void Function(String keyword) onOpenSearch;

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: WatchStatus.tabOrder.length,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = AppLayout.of(context);
    final state = ref.watch(watchHistoryStateProvider);
    final bottomInset = AppScaffoldInsets.bottomOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.fromLTRB(
            layout.pagePadding,
            layout.isDesktop
                ? AppSpacing.md
                : MediaQuery.paddingOf(context).top + AppSpacing.sm,
            layout.pagePadding,
            AppSpacing.xs,
          ),
          child: _Header(
            total: state.total,
            activeCount: state.activeCount,
          ),
        ),
        _StatusTabBar(controller: _tabController, state: state),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            physics: const BouncingScrollPhysics(),
            children: <Widget>[
              for (final status in WatchStatus.tabOrder)
                _StatusTab(
                  key: ValueKey<WatchStatus>(status),
                  status: status,
                  bottomInset: bottomInset,
                  onOpenSearch: widget.onOpenSearch,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── 顶部 ────────────────────────────────────────────────────

class _Header extends ConsumerWidget {
  const _Header({
    required this.total,
    required this.activeCount,
  });

  final int total;
  final int activeCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text('我的片库', style: AppTypography.headlineSmall),
              const SizedBox(height: 2),
              Text(
                total == 0
                    ? '观看记录只保存在本机，离线可用'
                    : '$total 条记录 · 其中 $activeCount 条待看',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.inkTertiary,
                ),
              ),
            ],
          ),
        ),
        if (total > 0) const _ClearButton(),
      ],
    );
  }
}

/// 「清空」入口：区分"清空某分栏"与"清空全部"，全部走二次确认。
class _ClearButton extends ConsumerWidget {
  const _ClearButton();

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final recorder = context.findRenderObject();
    final anchor = recorder is RenderBox && recorder.hasSize
        ? recorder.localToGlobal(
            Offset(recorder.size.width - 16, recorder.size.height),
          )
        : Offset.zero;

    final state = ref.read(watchHistoryStateProvider);
    final value = await AppMenu.showFor(
      context,
      globalPosition: anchor,
      title: '清理观看记录',
      actions: <AppMenuAction>[
        AppMenuAction(
          value: WatchStatus.watched.storageKey,
          label: '清空「已看」（${state.watched.length}）',
          icon: Icons.history_rounded,
          enabled: state.watched.isNotEmpty,
        ),
        AppMenuAction(
          value: WatchStatus.wantToWatch.storageKey,
          label: '清空「想看」（${state.wantToWatchList.length}）',
          icon: Icons.bookmarks_outlined,
          enabled: state.wantToWatchList.isNotEmpty,
        ),
        const AppMenuAction(
          value: 'all',
          label: '清空全部记录',
          icon: Icons.delete_sweep_outlined,
          destructive: true,
        ),
      ],
    );

    if (!context.mounted || value == null) return;
    final notifier = ref.read(watchHistoryProvider.notifier);

    if (value == 'all') {
      final confirmed = await showConfirmDialog(
        context,
        title: '清空全部观看记录？',
        message: '将同时清除「正在看」「想看」「已看」三个分栏，'
            '共 ${state.total} 条。该操作不可撤销。',
        confirmLabel: '清空',
        destructive: true,
        icon: Icons.warning_amber_rounded,
      );
      if (!confirmed || !context.mounted) return;
      await runWatchAction(
        context,
        action: notifier.clear,
        successMessage: '已清空全部观看记录',
      );
      return;
    }

    final status = WatchStatus.fromStorage(value);
    // 分栏计数即待删除条数：removeByStatus 删除的正是该状态的全部记录，
    // 因此无需等返回值再拼提示文案
    final doomed = state.countOf(status);
    final confirmed = await showConfirmDialog(
      context,
      title: '清空「${status.label}」？',
      message: '将移除该分栏下的全部记录（$doomed 条），该操作不可撤销。',
      confirmLabel: '清空',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    await runWatchAction(
      context,
      action: () => notifier.removeByStatus(status),
      successMessage: '已移除 $doomed 条「${status.label}」记录',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Builder(
      builder: (buttonContext) => TextButton.icon(
        onPressed: () => _open(buttonContext, ref),
        icon: const Icon(Icons.cleaning_services_outlined, size: 16),
        label: const Text('清空'),
        style: TextButton.styleFrom(foregroundColor: AppColors.inkSecondary),
      ),
    );
  }
}

// ── 分栏 Tab ────────────────────────────────────────────────

class _StatusTabBar extends StatelessWidget {
  const _StatusTabBar({required this.controller, required this.state});

  final TabController controller;
  final WatchHistoryState state;

  @override
  Widget build(BuildContext context) {
    final layout = AppLayout.of(context);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: layout.pagePadding),
      child: TabBar(
        controller: controller,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        indicatorSize: TabBarIndicatorSize.label,
        indicatorColor: AppColors.accent,
        indicatorWeight: 2,
        dividerColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
        overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
        labelColor: AppColors.accent,
        unselectedLabelColor: AppColors.inkTertiary,
        labelStyle: const TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w500,
        ),
        labelPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 0,
        ),
        tabs: <Widget>[
          for (final status in WatchStatus.tabOrder)
            Tab(
              height: 42,
              text: '${status.label} (${state.countOf(status)})',
            ),
        ],
      ),
    );
  }
}

// ── 分栏内容 ────────────────────────────────────────────────

class _StatusTab extends ConsumerWidget {
  const _StatusTab({
    super.key,
    required this.status,
    required this.bottomInset,
    required this.onOpenSearch,
  });

  final WatchStatus status;
  final double bottomInset;
  final void Function(String keyword) onOpenSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loading = ref.watch(watchHistoryProvider).isLoading;
    final records = ref.watch(watchHistoryStateProvider).of(status);

    // 首次加载：骨架屏。数量与列数无关，仅需填满首屏
    if (loading && records.isEmpty) {
      return const CustomScrollView(
        slivers: <Widget>[
          SliverPadding(
            padding: EdgeInsets.only(top: AppSpacing.md),
            sliver: SliverPosterSkeletonGrid(count: 10),
          ),
        ],
      );
    }

    if (records.isEmpty) {
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: <Widget>[
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: _emptyState(status),
            ),
          ),
        ],
      );
    }

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: <Widget>[
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),
        SliverPosterGrid(
          itemCount: records.length,
          itemBuilder: (context, index) => _RecordCard(record: records[index]),
        ),
        SliverToBoxAdapter(
          child: SizedBox(height: bottomInset + AppSpacing.xl),
        ),
      ],
    );
  }

  Widget _emptyState(WatchStatus status) {
    switch (status) {
      case WatchStatus.watching:
        return EmptyState(
          icon: Icons.play_circle_outline_rounded,
          title: '还没有在看的影片',
          description: '播放任意影片后，进度会自动记录在「正在看」，\n'
              '下次可以从上次的位置继续。',
          action: OutlinedButton.icon(
            onPressed: () => onOpenSearch(''),
            icon: const Icon(Icons.search_rounded, size: 16),
            label: const Text('去搜索'),
          ),
        );
      case WatchStatus.wantToWatch:
        return EmptyState(
          icon: Icons.bookmarks_outlined,
          title: '「想看」清单是空的',
          description: '在影视详情页把影片标记为「想看」，\n'
              '就会出现在这里，随时找得到。',
          action: OutlinedButton.icon(
            onPressed: () => onOpenSearch(''),
            icon: const Icon(Icons.search_rounded, size: 16),
            label: const Text('去搜索'),
          ),
        );
      case WatchStatus.watched:
        return const EmptyState(
          icon: Icons.task_alt_rounded,
          title: '还没有看完的影片',
          description: '播放进度超过 90% 后会自动归入「已看」，\n'
              '也可以手动标记。',
        );
    }
  }
}

// ── 记录卡片 ────────────────────────────────────────────────

/// 单条记录卡片。
///
/// 三种状态共用同一套卡片，仅"叠加信息"不同：
/// * 正在看 → 底部进度条 + `第 3 集 · 已看 65%`，点击直接续播；
/// * 想看   → 干净海报，点击进详情；
/// * 已看   → 左上角「已看」角标，点击进详情。
class _RecordCard extends ConsumerWidget {
  const _RecordCard({required this.record});

  final WatchRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = record.status;
    final isWatching = status.isWatching;
    final card = PosterCard(
      movie: _asMovie(record),
      showSourceCount: false,
      // 仅「正在看」叠加进度；「想看」无进度，「已看」进度条已无意义
      progress: isWatching ? record.percent : null,
      progressLabel: isWatching ? record.progressLabel : null,
      sourceBadge: status.isWatched ? '已看' : null,
      onTap: () => _open(context, ref),
      onPlay: isWatching ? () => _resume(context) : null,
      menuActionsBuilder: () => _menuActions(status),
      onMenuSelected: (value) => _handleMenu(context, ref, value),
    );

    return Dismissible(
      key: ValueKey<String>('record_${record.id}'),
      direction: DismissDirection.endToStart,
      background: const _DismissBackground(),
      secondaryBackground: const _DismissBackground(),
      // 只在确认阶段弹窗；真正的删除交给 onDismissed，
      // 保证动画播完后列表才变化，不会触发「已 dismiss 但仍在树中」的框架断言。
      confirmDismiss: (_) => _confirmRemove(context),
      onDismissed: (_) => _remove(context, ref),
      child: card,
    );
  }

  // ── 导航 ────────────────────────────────────────────────

  /// 点击卡片：正在看 → 直接续播；其余 → 进详情。
  void _open(BuildContext context, WidgetRef ref) {
    if (record.status.isWatching && record.shouldResume) {
      _resume(context);
      return;
    }
    AppRoutes.openDetail(
      context,
      sourceKey: record.sourceKey,
      vodId: record.vodId,
      seed: _asMovie(record),
    );
  }

  /// 续播：把线路与集数一起带进详情页，详情页会自动定位。
  void _resume(BuildContext context) => AppRoutes.openDetail(
        context,
        sourceKey: record.sourceKey,
        vodId: record.vodId,
        seed: _asMovie(record),
        resumeSourceFlag:
            record.playSourceFlag.isEmpty ? null : record.playSourceFlag,
        resumeEpisodeIndex: record.currentEpisodeIndex,
      );

  // ── 操作 ────────────────────────────────────────────────

  List<AppMenuAction> _menuActions(WatchStatus status) => <AppMenuAction>[
        if (status.isWatching)
          const AppMenuAction(
            value: 'resume',
            label: '继续播放',
            icon: Icons.play_arrow_rounded,
          ),
        const AppMenuAction(
          value: 'detail',
          label: '查看详情',
          icon: Icons.info_outline_rounded,
        ),
        if (!status.isWatched)
          const AppMenuAction(
            value: 'watched',
            label: '标记为已看',
            icon: Icons.task_alt_rounded,
          ),
        if (!status.isWantToWatch)
          const AppMenuAction(
            value: 'want',
            label: '移入「想看」',
            icon: Icons.bookmarks_outlined,
          ),
        const AppMenuAction(
          value: 'remove',
          label: '移出记录',
          icon: Icons.delete_outline_rounded,
          destructive: true,
        ),
      ];

  Future<void> _handleMenu(
    BuildContext context,
    WidgetRef ref,
    String value,
  ) async {
    final notifier = ref.read(watchHistoryProvider.notifier);
    final movie = _asMovie(record);

    switch (value) {
      case 'resume':
        _resume(context);
      case 'detail':
        AppRoutes.openDetail(
          context,
          sourceKey: record.sourceKey,
          vodId: record.vodId,
          seed: movie,
        );
      case 'watched':
        await runWatchAction(
          context,
          action: () => notifier.markWatched(movie),
          successMessage: '已把「${record.title}」标记为已看',
        );
      case 'want':
        await runWatchAction(
          context,
          action: () => notifier.setStatus(movie, WatchStatus.wantToWatch),
          successMessage: '已把「${record.title}」移入想看',
        );
      case 'remove':
        if (!context.mounted) return;
        if (!await _confirmRemove(context)) return;
        await runWatchAction(
          context,
          action: () => notifier.remove(record.id),
          successMessage: '已移出「${record.title}」',
        );
    }
  }

  Future<bool> _confirmRemove(BuildContext context) => showConfirmDialog(
        context,
        title: '移出观看记录？',
        message: '「${record.title}」的进度与状态将被删除，该操作不可撤销。',
        confirmLabel: '移出',
        destructive: true,
        icon: Icons.delete_outline_rounded,
      );

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    await runWatchAction(
      context,
      action: () => ref.read(watchHistoryProvider.notifier).remove(record.id),
      successMessage: '已移出「${record.title}」',
    );
  }

  /// 把记录投影为 [Movie] 以复用海报卡片。
  ///
  /// 只填海报卡片需要的字段；线路与选集数据不在本地，
  /// 因此点击时的 [Movie.sources] 为空，详情页会走网络补全。
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
}

/// 左滑时露出的删除底衬。
class _DismissBackground extends StatelessWidget {
  const _DismissBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.dangerSoft,
        borderRadius: AppRadius.cardBR,
      ),
      child: const Icon(
        Icons.delete_outline_rounded,
        size: 22,
        color: AppColors.danger,
      ),
    );
  }
}
