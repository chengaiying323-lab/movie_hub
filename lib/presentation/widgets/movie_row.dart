import 'package:flutter/material.dart';

import '../../core/design/design.dart';
import '../../domain/entities/movie.dart';
import 'app_menu.dart';
import 'empty_state.dart';
import 'poster_card.dart';
import 'section_header.dart';
import 'shimmer.dart';

/// 横向滑动影片栏（首页推荐分区）。
///
/// 跨平台交互
/// ------------------------------------------------------------------
/// - **桌面端**：整栏悬停时左右两侧淡入圆形箭头按钮（点击翻页一屏），
///   同时保留鼠标滚轮横向滚动与触控板双指横滑；
/// - **移动端**：纯手势横滑，不显示箭头（触屏上的箭头按钮是反模式）。
class MovieRow extends StatefulWidget {
  const MovieRow({
    super.key,
    required this.title,
    required this.movies,
    required this.onTap,
    this.subtitle,
    this.onPlay,
    this.sourceBadgeBuilder,
    this.menuActionsBuilder,
    this.onMenuSelected,
    this.onShowAll,
    this.loading = false,
    this.skeletonCount = 8,
    this.padding,
  });

  final String title;
  final String? subtitle;
  final List<Movie> movies;
  final void Function(Movie movie) onTap;
  final void Function(Movie movie)? onPlay;
  final String? Function(Movie movie)? sourceBadgeBuilder;
  final List<AppMenuAction> Function(Movie movie)? menuActionsBuilder;
  final void Function(Movie movie, String value)? onMenuSelected;
  final VoidCallback? onShowAll;
  final bool loading;
  final int skeletonCount;

  /// 页面水平内边距（默认取布局断点值）。
  final double? padding;

  @override
  State<MovieRow> createState() => _MovieRowState();
}

class _MovieRowState extends State<MovieRow> {
  final ScrollController _controller = ScrollController();
  bool _rowHovered = false;
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateScrollState);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollState());
  }

  @override
  void dispose() {
    _controller.removeListener(_updateScrollState);
    _controller.dispose();
    super.dispose();
  }

  void _updateScrollState() {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final canLeft = position.pixels > 0;
    final canRight = position.pixels < position.maxScrollExtent - 1;
    if (canLeft == _canScrollLeft && canRight == _canScrollRight) return;
    setState(() {
      _canScrollLeft = canLeft;
      _canScrollRight = canRight;
    });
  }

  /// 翻一屏（约等于可见卡片数量）。
  void _page(double direction) {
    if (!_controller.hasClients) return;
    final viewport = _controller.position.viewportDimension;
    final target = (_controller.offset + viewport * direction).clamp(
      _controller.position.minScrollExtent,
      _controller.position.maxScrollExtent,
    );
    _controller.animateTo(
      target,
      duration: AppMotion.slow,
      curve: AppMotion.standard,
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = AppLayout.of(context);
    final padding = widget.padding ?? layout.pagePadding;

    // 单卡宽度：按"单屏可见数量"反推，并限制在合理区间，
    // 避免超宽屏上卡片被拉成巨幅、窄屏上卡片过小。
    final screenWidth = MediaQuery.sizeOf(context).width;
    final railWidth = layout.isDesktop ? AppSizes.railWidth : 0.0;
    final visible = layout.rowVisibleCount;
    final rawWidth =
        (screenWidth - railWidth - padding * 2 - AppSpacing.sm * (visible - 1)) /
            visible;
    final itemWidth = rawWidth.clamp(128.0, 208.0);
    final rowHeight =
        itemWidth / AppSizes.posterAspectRatio + AppSizes.rowTextExtent;

    final showArrows = layout.isDesktop;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.fromLTRB(padding, 0, padding, 0),
          child: SectionHeader(
            title: widget.title,
            subtitle: widget.subtitle,
            trailing: SectionMoreButton(onTap: widget.onShowAll),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        MouseRegion(
          onEnter: (_) => setState(() => _rowHovered = true),
          onExit: (_) => setState(() => _rowHovered = false),
          child: SizedBox(
            height: rowHeight,
            child: Stack(
              children: <Widget>[
                if (widget.loading && widget.movies.isEmpty)
                  _buildSkeletonList(padding, itemWidth)
                else if (widget.movies.isEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: padding),
                    child: const SectionEmpty(),
                  )
                else
                  ListView.separated(
                    controller: _controller,
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(horizontal: padding),
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    itemCount: widget.movies.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(width: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final movie = widget.movies[index];
                      return SizedBox(
                        width: itemWidth,
                        child: PosterCard(
                          movie: movie,
                          onTap: () => widget.onTap(movie),
                          onPlay: widget.onPlay == null
                              ? null
                              : () => widget.onPlay!(movie),
                          sourceBadge: widget.sourceBadgeBuilder?.call(movie),
                          showSourceCount: false,
                          menuActionsBuilder: widget.menuActionsBuilder == null
                              ? null
                              : () => widget.menuActionsBuilder!(movie),
                          onMenuSelected: widget.onMenuSelected == null
                              ? null
                              : (value) =>
                                  widget.onMenuSelected!(movie, value),
                        ),
                      );
                    },
                  ),

                // 左右翻页箭头（仅桌面端，整栏悬停时淡入）
                if (showArrows && !(widget.loading && widget.movies.isEmpty))
                  _RowArrow(
                    left: true,
                    visible: _rowHovered && _canScrollLeft,
                    onTap: () => _page(-1),
                  ),
                if (showArrows && !(widget.loading && widget.movies.isEmpty))
                  _RowArrow(
                    left: false,
                    visible: _rowHovered && _canScrollRight,
                    onTap: () => _page(1),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSkeletonList(double padding, double itemWidth) {
    // 骨架宽度与真实卡片一致，避免加载完成后的横向跳动
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: padding),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: widget.skeletonCount,
      separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
      itemBuilder: (_, __) => SizedBox(width: itemWidth, child: const PosterSkeleton()),
    );
  }
}

/// 横向栏的翻页箭头：圆形白色毛玻璃按钮 + 轻阴影。
class _RowArrow extends StatelessWidget {
  const _RowArrow({
    required this.left,
    required this.visible,
    required this.onTap,
  });

  final bool left;
  final bool visible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      bottom: AppSizes.rowTextExtent,
      left: left ? AppSpacing.xs : null,
      right: left ? null : AppSpacing.xs,
      child: Center(
        child: IgnorePointer(
          ignoring: !visible,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: AppMotion.fast,
            curve: AppMotion.standard,
            child: Material(
              color: AppColors.surface,
              shape: const CircleBorder(
                side: BorderSide(
                  color: AppColors.hairline,
                  width: AppStroke.hairline,
                ),
              ),
              elevation: 0,
              child: InkWell(
                onTap: onTap,
                customBorder: const CircleBorder(),
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: Icon(
                    left
                        ? Icons.chevron_left_rounded
                        : Icons.chevron_right_rounded,
                    size: 20,
                    color: AppColors.inkSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
