import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/design/design.dart';
import '../../domain/entities/movie.dart';
import 'poster_image.dart';

/// 顶部焦点图（Hero Banner）。
///
/// 浅色渐变方案
/// ------------------------------------------------------------------
/// 焦点图需要在"展示剧照"与"保证深色文字可读"之间取得平衡。
/// 因此叠加两层浅色渐变而非深色遮罩：
/// 1. **垂直渐变**：底部 55% 由 `canvas` 实色渐隐至透明，
///    使焦点图自然"融入"页面底色，消除生硬的矩形边界；
/// 2. **水平渐变**：左半侧由 `canvas` 半透明渐隐至透明，
///    为左侧的文字与按钮提供干净的浅色底衬。
///
/// 交互：桌面端悬停暂停自动轮播；点击圆点直接跳页。
class HeroBanner extends StatefulWidget {
  const HeroBanner({
    super.key,
    required this.movies,
    required this.onTap,
    this.onPlay,
    this.height,
    this.autoPlay = true,
  });

  final List<Movie> movies;
  final void Function(Movie movie) onTap;
  final void Function(Movie movie)? onPlay;
  final double? height;
  final bool autoPlay;

  @override
  State<HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<HeroBanner> {
  final PageController _controller = PageController();
  Timer? _timer;
  int _index = 0;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    _restartTimer();
  }

  @override
  void didUpdateWidget(covariant HeroBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.movies.length != widget.movies.length) {
      _index = 0;
      if (_controller.hasClients) _controller.jumpToPage(0);
      _restartTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _restartTimer() {
    _timer?.cancel();
    if (!widget.autoPlay || widget.movies.length < 2) return;
    _timer = Timer.periodic(AppMotion.bannerAutoPlay, (_) {
      if (_paused || !mounted || !_controller.hasClients) return;
      final next = (_index + 1) % widget.movies.length;
      _controller.animateToPage(
        next,
        duration: AppMotion.slow,
        curve: AppMotion.standard,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.movies.isEmpty) return const SizedBox.shrink();

    final layout = AppLayout.of(context);
    final height = widget.height ??
        (layout.isLargeScreen
            ? AppSizes.bannerHeightDesktop
            : AppSizes.bannerHeightMobile);
    final padding = layout.pagePadding;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: padding),
      child: SizedBox(
        height: height,
        child: MouseRegion(
          onEnter: (_) => _paused = true,
          onExit: (_) => _paused = false,
          child: Stack(
            children: <Widget>[
              // 焦点图主体
              ClipRRect(
                borderRadius: AppRadius.panelBR,
                child: PageView.builder(
                  controller: _controller,
                  physics: const BouncingScrollPhysics(),
                  onPageChanged: (value) => setState(() => _index = value),
                  itemCount: widget.movies.length,
                  itemBuilder: (context, index) => _Slide(
                    movie: widget.movies[index],
                    compact: !layout.isLargeScreen,
                    onTap: () => widget.onTap(widget.movies[index]),
                    onPlay: widget.onPlay == null
                        ? null
                        : () => widget.onPlay!(widget.movies[index]),
                  ),
                ),
              ),

              // 发丝描边
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: AppRadius.panelBR,
                      border: Border.all(
                        color: AppColors.hairline,
                        width: AppStroke.hairline,
                        strokeAlign: BorderSide.strokeAlignInside,
                      ),
                    ),
                  ),
                ),
              ),

              // 指示圆点
              if (widget.movies.length > 1)
                Positioned(
                  right: AppSpacing.lg,
                  bottom: AppSpacing.md,
                  child: _Dots(
                    count: widget.movies.length,
                    active: _index,
                    onSelect: (i) => _controller.animateToPage(
                      i,
                      duration: AppMotion.slow,
                      curve: AppMotion.standard,
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

class _Slide extends StatefulWidget {
  const _Slide({
    required this.movie,
    required this.compact,
    required this.onTap,
    this.onPlay,
  });

  final Movie movie;
  final bool compact;
  final VoidCallback onTap;
  final VoidCallback? onPlay;

  @override
  State<_Slide> createState() => _SlideState();
}

class _SlideState extends State<_Slide> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final movie = widget.movie;
    final imageUrl = (movie.backdrop ?? '').trim().isNotEmpty
        ? movie.backdrop!
        : movie.poster;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // 剧照（极缓慢放大，营造"呼吸感"）
            AnimatedScale(
              scale: _hovered ? 1.03 : 1.0,
              duration: AppMotion.slow,
              curve: AppMotion.soft,
              child: PosterImage(
                url: imageUrl,
                title: movie.title,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                placeholderIcon: Icons.local_movies_outlined,
              ),
            ),

            // 垂直渐变：底部融入页面底色
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Color(0x00F5F6F8),
                    Color(0x66F5F6F8),
                    Color(0xF2F5F6F8),
                    AppColors.canvas,
                  ],
                  stops: <double>[0.20, 0.52, 0.82, 1.0],
                ),
              ),
            ),

            // 水平渐变：为左侧文字提供浅色底衬
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: <Color>[
                    Color(0xE6F5F6F8),
                    Color(0x99F5F6F8),
                    Color(0x00F5F6F8),
                  ],
                  stops: <double>[0.0, 0.42, 0.78],
                ),
              ),
            ),

            // 文案与操作区
            Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  widget.compact ? AppSpacing.md : AppSpacing.xl,
                  0,
                  widget.compact ? AppSpacing.md : AppSpacing.xl,
                  widget.compact ? AppSpacing.md : AppSpacing.lg,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: widget.compact ? 320 : 520,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        movie.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.detailTitle.copyWith(
                          fontSize: widget.compact ? 20 : 26,
                        ),
                      ),
                      if (movie.displaySubtitle.isNotEmpty) ...<Widget>[
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          movie.displaySubtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.posterMeta.copyWith(
                            fontSize: 12.5,
                            color: AppColors.inkSecondary,
                          ),
                        ),
                      ],
                      if (!widget.compact &&
                          (movie.description ?? '').isNotEmpty) ...<Widget>[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          movie.description!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.6,
                            color: AppColors.inkTertiary,
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: <Widget>[
                          _ActionButton(
                            label: '立即播放',
                            icon: Icons.play_arrow_rounded,
                            primary: true,
                            onTap: widget.onPlay ?? widget.onTap,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          _ActionButton(
                            label: '详情',
                            icon: Icons.info_outline_rounded,
                            onTap: widget.onTap,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.primary
        ? (_pressed ? AppColors.accentPressed : AppColors.accent)
        : (_pressed
            ? AppColors.surfaceMuted
            : (_hovered ? AppColors.surface : AppColors.surface.withOpacity(0.86)));
    final fg = widget.primary ? AppColors.inkOnDark : AppColors.ink;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.standard,
          transform: Matrix4.translationValues(
            0,
            _hovered && !_pressed ? -1.5 : 0,
            0,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 9,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: AppRadius.smBR,
            border: widget.primary
                ? null
                : Border.all(
                    color: AppColors.hairlineStrong,
                    width: AppStroke.hairline,
                  ),
            boxShadow: widget.primary
                ? AppShadows.tinted(
                    AppColors.accent,
                    opacity: _hovered ? 0.3 : 0.2,
                  )
                : AppShadows.card,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(widget.icon, size: 17, color: fg),
              const SizedBox(width: 5),
              Text(
                widget.label,
                style: AppTypography.button.copyWith(
                  fontSize: 13,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 轮播指示圆点：当前项为品牌色长条，其余为浅灰圆点。
class _Dots extends StatelessWidget {
  const _Dots({
    required this.count,
    required this.active,
    required this.onSelect,
  });

  final int count;
  final int active;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var i = 0; i < count; i++)
          GestureDetector(
            onTap: () => onSelect(i),
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: AppMotion.normal,
              curve: AppMotion.standard,
              margin: const EdgeInsets.only(left: AppSpacing.xxs),
              width: i == active ? 16 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == active
                    ? AppColors.accent
                    : AppColors.inkDisabled.withOpacity(0.6),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
      ],
    );
  }
}
