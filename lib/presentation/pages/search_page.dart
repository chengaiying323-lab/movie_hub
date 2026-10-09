import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/design.dart';
import '../../domain/entities/movie.dart';
import '../../domain/entities/search_result.dart';
import '../../domain/entities/watch_record.dart';
import '../app_navigation.dart';
import '../providers/search_providers.dart';
import '../providers/watch_history_providers.dart';
import '../widgets/adaptive_scaffold.dart';
import '../widgets/app_menu.dart';
import '../widgets/empty_state.dart';
import '../widgets/poster_card.dart';
import '../widgets/poster_grid.dart';
import '../widgets/search_capsule.dart';
import '../widgets/watch_status_button.dart';

/// 搜索页。
///
/// 交互亮点
/// ------------------------------------------------------------------
/// 1. **流式刷新**：接入第一阶段的 `searchStream`，每个源返回即刷新一次结果，
///    用户不必等待最慢的源（顶部的细进度条提示"仍在检索"）；
/// 2. **分源 Tab**：把"哪个源返回了什么"直接摆到界面上，
///    失败的源也保留在 Tab 中并标注原因——聚合结果的透明度是信任的基础；
/// 3. **桌面端快捷方式**：`Ctrl/Cmd + K` 聚焦、`Esc` 清空。
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit(String keyword) {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return;
    // 回填输入框（历史标签点击场景）
    if (_controller.text != trimmed) _controller.text = trimmed;
    _focusNode.unfocus();
    ref.read(searchQueryProvider.notifier).state = trimmed;
    ref.read(searchResultProvider.notifier).search(trimmed);
  }

  void _clearAll() {
    _controller.clear();
    ref.read(searchQueryProvider.notifier).state = '';
    ref.read(searchResultProvider.notifier).clear();
  }

  @override
  Widget build(BuildContext context) {
    final layout = AppLayout.of(context);
    final resultState = ref.watch(searchResultProvider);
    final streaming = ref.watch(searchStreamingProvider);
    final bottomInset = AppScaffoldInsets.bottomOf(context);
    final hasResult = resultState.valueOrNull != null;

    return SearchShortcutScope(
      focusNode: _focusNode,
      onEscape: _clearAll,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: <Widget>[
          // ── 顶部：搜索胶囊 ──────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                layout.pagePadding,
                layout.isDesktop
                    ? AppSpacing.md
                    : MediaQuery.paddingOf(context).top + AppSpacing.sm,
                layout.pagePadding,
                AppSpacing.sm,
              ),
              child: SearchCapsule(
                controller: _controller,
                focusNode: _focusNode,
                onSubmitted: _submit,
                onClear: () {
                  ref.read(searchResultProvider.notifier).clear();
                },
              ),
            ),
          ),

          // ── 流式检索进度条 ──────────────────────────────
          SliverToBoxAdapter(
            child: AnimatedSize(
              duration: AppMotion.normal,
              curve: AppMotion.standard,
              child: streaming
                  ? const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                      ),
                      child: ClipRRect(
                        borderRadius: AppRadius.pillBR,
                        child: LinearProgressIndicator(
                          minHeight: 2,
                          backgroundColor: AppColors.surfaceSunken,
                        ),
                      ),
                    )
                  : const SizedBox(height: 2),
            ),
          ),

          // ── 选项与分源 Tab ─────────────────────────────
          if (hasResult)
            const SliverToBoxAdapter(child: _SearchToolbar())
          else
            SliverToBoxAdapter(
              child: _HistorySection(onSelect: _submit, onClear: _clearAll),
            ),

          // ── 结果区 ─────────────────────────────────────
          ...resultState.when(
            loading: () => const <Widget>[
              SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),
              SliverPosterSkeletonGrid(count: 12),
            ],
            error: (error, _) => <Widget>[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.xxl,
                  ),
                  child: ErrorView(
                    message: '$error',
                    onRetry: () => _submit(_controller.text),
                  ),
                ),
              ),
            ],
            data: (result) {
              if (result == null) return const <Widget>[];
              final items = ref.watch(filteredSearchItemsProvider);
              if (items.isEmpty) {
                final failed = result.failedReports.length;
                return <Widget>[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.xxl,
                      ),
                      child: EmptyState(
                        icon: Icons.search_off_rounded,
                        title: streaming ? '正在检索…' : '没有找到相关结果',
                        description: failed > 0
                            ? '当前有 $failed 个数据源未返回结果，'
                                '可在下方分源标签中查看具体原因。'
                            : '换个关键词试试，或到「数据源」页补充更多源。',
                      ),
                    ),
                  ),
                ];
              }
              return <Widget>[
                SliverToBoxAdapter(
                  child: SizedBox(height: AppSpacing.md),
                ),
                SliverPosterGrid(
                  itemCount: items.length,
                  itemBuilder: (context, index) => _buildCard(items[index]),
                ),
              ];
            },
          ),

          SliverToBoxAdapter(
            child: SizedBox(height: bottomInset + AppSpacing.xl),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(AggregatedMovie item) {
    final Movie movie = item.primary;
    final status = ref.watch(watchStatusProvider(movie.id));

    return PosterCard(
      movie: movie,
      sourceBadge: movie.sourceName,
      showSourceCount: item.sourceCount > 1,
      onTap: () => _openDetail(item),
      onPlay: () => _openDetail(item),
      menuActionsBuilder: () => <AppMenuAction>[
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
          value: 'copy',
          label: '复制片名',
          icon: Icons.copy_rounded,
        ),
      ],
      onMenuSelected: (value) => _handleMenu(item, movie, value),
    );
  }

  void _openDetail(AggregatedMovie item) => AppRoutes.openAggregated(
        context,
        primary: item.primary,
        merged: item.merged,
      );

  Future<void> _handleMenu(
    AggregatedMovie item,
    Movie movie,
    String value,
  ) async {
    final notifier = ref.read(watchHistoryProvider.notifier);

    switch (value) {
      case 'detail':
        _openDetail(item);
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
      case 'copy':
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('片名：${movie.title}')),
        );
    }
  }
}

// ── 搜索选项 + 分源 Tab ─────────────────────────────────────

class _SearchToolbar extends ConsumerWidget {
  const _SearchToolbar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = AppLayout.of(context);
    final options = ref.watch(sourceFilterOptionsProvider);
    final selected = ref.watch(selectedSourceFilterProvider);
    final result = ref.watch(searchResultProvider).valueOrNull;
    final quick = ref.watch(quickSearchProvider);
    final progressive = ref.watch(progressiveSearchProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.fromLTRB(
            layout.pagePadding,
            AppSpacing.xs,
            layout.pagePadding,
            AppSpacing.xs,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  result == null
                      ? ''
                      : '${result.items.length} 部 · '
                          '${result.successCount} 源成功'
                          '${result.failureCount > 0 ? ' / ${result.failureCount} 源失败' : ''}'
                          ' · ${result.totalElapsedMs}ms',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.posterMeta,
                ),
              ),
              _ToggleChip(
                label: '流式',
                icon: Icons.bolt_outlined,
                active: progressive,
                tooltip: '每完成一个源立即刷新结果',
                onTap: () {
                  ref.read(progressiveSearchProvider.notifier).state =
                      !progressive;
                  final keyword = ref.read(searchQueryProvider);
                  if (keyword.isNotEmpty) {
                    ref.read(searchResultProvider.notifier).search(keyword);
                  }
                },
              ),
              const SizedBox(width: AppSpacing.xs),
              _ToggleChip(
                label: '极速',
                icon: Icons.speed_rounded,
                active: quick,
                tooltip: '只检索优先级最高的 5 个源',
                onTap: () {
                  ref.read(quickSearchProvider.notifier).state = !quick;
                  final keyword = ref.read(searchQueryProvider);
                  if (keyword.isNotEmpty) {
                    ref.read(searchResultProvider.notifier).search(keyword);
                  }
                },
              ),
            ],
          ),
        ),

        // 分源 Tab
        if (options.isNotEmpty)
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: layout.pagePadding),
              physics: const BouncingScrollPhysics(),
              itemCount: options.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xs),
              itemBuilder: (context, index) {
                final option = options[index];
                return _SourceTab(
                  option: option,
                  selected: option.sourceKey == selected,
                  onTap: () {
                    ref.read(selectedSourceFilterProvider.notifier).state =
                        option.sourceKey;
                  },
                );
              },
            ),
          ),
        const SizedBox(height: AppSpacing.xs),
      ],
    );
  }
}

class _ToggleChip extends StatefulWidget {
  const _ToggleChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    this.tooltip,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  State<_ToggleChip> createState() => _ToggleChipState();
}

class _ToggleChipState extends State<_ToggleChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final content = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.standard,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: widget.active
                ? AppColors.accentSoft
                : (_hovered ? AppColors.surfaceMuted : Colors.transparent),
            borderRadius: AppRadius.xsBR,
            border: Border.all(
              color: widget.active ? AppColors.accentSoft : AppColors.hairline,
              width: AppStroke.hairline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                widget.icon,
                size: 14,
                color: widget.active
                    ? AppColors.accent
                    : AppColors.inkTertiary,
              ),
              const SizedBox(width: 4),
              Text(
                widget.label,
                style: AppTypography.posterMeta.copyWith(
                  color:
                      widget.active ? AppColors.accent : AppColors.inkTertiary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (widget.tooltip == null) return content;
    return Tooltip(message: widget.tooltip!, child: content);
  }
}

/// 分源 Tab：显示源名、命中数量与可用状态。
class _SourceTab extends StatefulWidget {
  const _SourceTab({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final SourceFilterOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SourceTab> createState() => _SourceTabState();
}

class _SourceTabState extends State<_SourceTab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final option = widget.option;
    final selected = widget.selected;
    final failed = !option.ok;

    final textColor = selected
        ? AppColors.accent
        : (failed ? AppColors.inkTertiary : AppColors.inkSecondary);

    Widget tab = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.standard,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accentSoft
                : (_hovered ? AppColors.surfaceMuted : AppColors.surface),
            borderRadius: AppRadius.pillBR,
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.hairline,
              width: selected ? AppStroke.emphasis : AppStroke.hairline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (failed)
                const Padding(
                  padding: EdgeInsets.only(right: 5),
                  child: Icon(
                    Icons.error_outline_rounded,
                    size: 13,
                    color: AppColors.danger,
                  ),
                )
              else if (!option.isAll)
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 5),
                  decoration: const BoxDecoration(
                    color: AppColors.positive,
                    shape: BoxShape.circle,
                  ),
                ),
              Text(
                option.label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (failed && (option.errorMessage ?? '').isNotEmpty) {
      tab = Tooltip(
        message: '${option.name}：${option.errorMessage}',
        child: tab,
      );
    }
    return tab;
  }
}

// ── 搜索历史 ────────────────────────────────────────────────

class _HistorySection extends ConsumerWidget {
  const _HistorySection({required this.onSelect, required this.onClear});

  final void Function(String keyword) onSelect;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = AppLayout.of(context);
    final historyState = ref.watch(searchHistoryProvider);
    final history = historyState.valueOrNull ?? const <String>[];

    if (history.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: layout.pagePadding,
          vertical: AppSpacing.xxl,
        ),
        child: const EmptyState(
          icon: Icons.travel_explore_rounded,
          title: '输入关键词开始多源检索',
          description: '同一部影片会在多个数据源中同时查找，'
              '结果自动去重合并，可一键切换线路。',
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: layout.pagePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Text('最近搜索', style: AppTypography.sectionTitle),
              const Spacer(),
              TextButton(
                onPressed: () {
                  ref.read(searchHistoryProvider.notifier).clear();
                  onClear();
                },
                child: const Text('清空'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              for (final keyword in history)
                _HistoryChip(
                  keyword: keyword,
                  onTap: () => onSelect(keyword),
                  onRemove: () =>
                      ref.read(searchHistoryProvider.notifier).remove(keyword),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HistoryChip extends StatefulWidget {
  const _HistoryChip({
    required this.keyword,
    required this.onTap,
    required this.onRemove,
  });

  final String keyword;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  State<_HistoryChip> createState() => _HistoryChipState();
}

class _HistoryChipState extends State<_HistoryChip> {
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
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            7,
            AppSpacing.xs,
            7,
          ),
          decoration: BoxDecoration(
            color: _hovered ? AppColors.accentSofter : AppColors.surface,
            borderRadius: AppRadius.pillBR,
            border: Border.all(
              color: _hovered ? AppColors.accentSoft : AppColors.hairline,
              width: AppStroke.hairline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                widget.keyword,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.inkSecondary,
                ),
              ),
              const SizedBox(width: AppSpacing.xxs),
              GestureDetector(
                onTap: widget.onRemove,
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(
                    Icons.close_rounded,
                    size: 13,
                    color: AppColors.inkDisabled,
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
