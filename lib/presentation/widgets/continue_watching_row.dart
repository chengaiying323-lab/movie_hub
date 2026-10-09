import 'package:flutter/material.dart';

import '../../core/design/design.dart';
import '../../domain/entities/movie.dart';
import '../../domain/entities/watch_record.dart';
import 'app_menu.dart';
import 'poster_card.dart';
import 'section_header.dart';

/// 「继续观看」横向栏。
///
/// 与 [MovieRow] 的区别：数据源是 [WatchRecord] 而非 `Movie`，
/// 卡片需要渲染"进度浮层"（底部进度条 + 已看到第几集），
/// 并提供「移除记录」这一专属操作。
class ContinueWatchingRow extends StatefulWidget {
  const ContinueWatchingRow({
    super.key,
    required this.items,
    required this.onResume,
    this.onRemove,
    this.onOpenDetail,
    this.padding,
  });

  final List<WatchRecord> items;

  /// 继续播放（直接进播放器 / 详情页续播）。
  final void Function(WatchRecord item) onResume;

  /// 移除观看记录。
  final void Function(WatchRecord item)? onRemove;

  /// 查看详情。
  final void Function(WatchRecord item)? onOpenDetail;

  final double? padding;

  @override
  State<ContinueWatchingRow> createState() => _ContinueWatchingRowState();
}

class _ContinueWatchingRowState extends State<ContinueWatchingRow> {
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
  void didUpdateWidget(covariant ContinueWatchingRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollState());
  }

  @override
  void dispose() {
    _controller.removeListener(_updateScrollState);
    _controller.dispose();
    super.dispose();
  }

  void _updateScrollState() {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    final canLeft = position.pixels > 0;
    final canRight = position.pixels < position.maxScrollExtent - 1;
    if (canLeft == _canScrollLeft && canRight == _canScrollRight) return;
    setState(() {
      _canScrollLeft = canLeft;
      _canScrollRight = canRight;
    });
  }

  void _page(double direction) {
    if (!_controller.hasClients) return;
    final viewport = _controller.position.viewportDimension;
    _controller.animateTo(
      (_controller.offset + viewport * direction).clamp(
        _controller.position.minScrollExtent,
        _controller.position.maxScrollExtent,
      ),
      duration: AppMotion.slow,
      curve: AppMotion.standard,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    final layout = AppLayout.of(context);
    final padding = widget.padding ?? layout.pagePadding;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final railWidth = layout.isDesktop ? AppSizes.railWidth : 0.0;
    final visible = layout.rowVisibleCount;
    final itemWidth = ((screenWidth -
                railWidth -
                padding * 2 -
                AppSpacing.sm * (visible - 1)) /
            visible)
        .clamp(128.0, 208.0);
    final rowHeight =
        itemWidth / AppSizes.posterAspectRatio + AppSizes.rowTextExtent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.symmetric(horizontal: padding),
          child: const SectionHeader(
            title: '继续观看',
            subtitle: '接着上次的进度',
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
                ListView.separated(
                  controller: _controller,
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: padding),
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  itemCount: widget.items.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final item = widget.items[index];
                    return SizedBox(
                      width: itemWidth,
                      child: PosterCard(
                        movie: _asMovie(item),
                        progress: item.percent,
                        progressLabel: item.progressLabel,
                        showSourceCount: false,
                        onTap: () => widget.onResume(item),
                        onPlay: () => widget.onResume(item),
                        menuActionsBuilder: () => <AppMenuAction>[
                          const AppMenuAction(
                            value: 'resume',
                            label: '继续播放',
                            icon: Icons.play_arrow_rounded,
                          ),
                          if (widget.onOpenDetail != null)
                            const AppMenuAction(
                              value: 'detail',
                              label: '查看详情',
                              icon: Icons.info_outline_rounded,
                            ),
                          if (widget.onRemove != null)
                            const AppMenuAction(
                              value: 'remove',
                              label: '移除观看记录',
                              icon: Icons.delete_outline_rounded,
                              destructive: true,
                            ),
                        ],
                        onMenuSelected: (value) {
                          if (value == 'resume') widget.onResume(item);
                          if (value == 'detail') widget.onOpenDetail?.call(item);
                          if (value == 'remove') widget.onRemove?.call(item);
                        },
                      ),
                    );
                  },
                ),
                if (layout.isDesktop) ...<Widget>[
                  _Arrow(
                    left: true,
                    visible: _rowHovered && _canScrollLeft,
                    onTap: () => _page(-1),
                  ),
                  _Arrow(
                    left: false,
                    visible: _rowHovered && _canScrollRight,
                    onTap: () => _page(1),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 把观看记录投影为 [Movie]，以复用海报卡片。
  ///
  /// 只填充卡片展示所需字段（标题 / 海报 / 年份 / 备注），不构造线路数据
  /// ——「继续观看」卡片不展示线路信息。
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

class _Arrow extends StatelessWidget {
  const _Arrow({
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
            child: Material(
              color: AppColors.surface,
              shape: const CircleBorder(
                side: BorderSide(
                  color: AppColors.hairline,
                  width: AppStroke.hairline,
                ),
              ),
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
