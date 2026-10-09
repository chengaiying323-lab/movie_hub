import 'package:flutter/material.dart';

import '../../core/design/design.dart';
import '../../domain/entities/movie.dart';
import 'app_menu.dart';
import 'poster_image.dart';

/// 海报卡片（标准 2:3 纵横比）。
///
/// 视觉规范
/// ------------------------------------------------------------------
/// - 圆角 [AppRadius.card]（14px）+ 0.5px 发丝描边 + 极轻弥散阴影；
/// - 静止时阴影几乎不可见，**悬停时上浮 4px 且阴影扩散**（桌面端）；
/// - 悬停时叠加极淡遮罩并浮现播放按钮，给出明确的"可点击"暗示；
/// - 支持底部进度条（继续观看场景）与右上角来源角标（聚合场景）。
///
/// 交互规范
/// ------------------------------------------------------------------
/// - 点击 → 进入详情 / 继续播放；
/// - 桌面端右键、移动端长按 → 快捷菜单（标记想看 / 正在看 / 已看等）。
class PosterCard extends StatefulWidget {
  const PosterCard({
    super.key,
    required this.movie,
    this.onTap,
    this.onPlay,
    this.sourceBadge,
    this.showSourceCount = true,
    this.progress,
    this.progressLabel,
    this.rank,
    this.showMeta = true,
    this.menuActionsBuilder,
    this.onMenuSelected,
    this.fit = BoxFit.cover,
  });

  final Movie movie;

  final VoidCallback? onTap;

  /// 悬停播放按钮的行为；为空时回退到 [onTap]。
  final VoidCallback? onPlay;

  /// 右上/左上角来源角标。
  final String? sourceBadge;

  /// 是否显示「N 线路」角标（跨源聚合时使用）。
  final bool showSourceCount;

  /// 播放进度 0.0~1.0；非空时在底部渲染进度条。
  final double? progress;

  /// 进度条上方的文案，如「第3集 · 12:30」。
  final String? progressLabel;

  /// 榜单序号（非空时左上角显示序号徽标）。
  final int? rank;

  final bool showMeta;

  /// 快捷菜单项构造器（由页面注入，因为观影状态属于页面层）。
  final List<AppMenuAction> Function()? menuActionsBuilder;
  final void Function(String value)? onMenuSelected;

  final BoxFit fit;

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  bool _hovered = false;
  bool _pressed = false;

  bool get _lifted => _hovered && !_pressed;

  void _setHover(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    // 悬停仅在桌面端启用：触屏上的"悬停"会残留，导致卡片卡在浮起态。
    final hoverSupported = AppLayout.of(context).isDesktop;

    Widget card = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: _buildPosterArea(hoverSupported)),
        if (widget.showMeta) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          SizedBox(height: 38, child: _buildMeta()),
        ],
      ],
    );

    if (widget.menuActionsBuilder != null) {
      card = card.withAppMenu(
        actionsBuilder: widget.menuActionsBuilder!,
        titleBuilder: () => widget.movie.title,
        onSelected: widget.onMenuSelected,
      );
    }

    return MouseRegion(
      cursor: widget.onTap == null
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      onEnter: hoverSupported ? (_) => _setHover(true) : null,
      onExit: hoverSupported ? (_) => _setHover(false) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: card,
      ),
    );
  }

  // ── 海报区域 ────────────────────────────────────────────

  Widget _buildPosterArea(bool hoverSupported) {
    final radius = AppRadius.cardBR;

    return AnimatedContainer(
      duration: AppMotion.fast,
      curve: AppMotion.standard,
      transform: Matrix4.translationValues(
        0,
        _lifted ? -AppMotion.hoverLift : 0,
        0,
      ),
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: _pressed
            ? AppShadows.cardPressed
            : (_lifted ? AppShadows.cardHover : AppShadows.card),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            PosterImage(
              url: widget.movie.poster,
              title: widget.movie.title,
              fit: widget.fit,
            ),

            // 悬停遮罩：极淡，仅用于把海报"压暗一点点"以突出播放按钮
            if (hoverSupported)
              IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _lifted ? 1 : 0,
                  duration: AppMotion.fast,
                  curve: AppMotion.standard,
                  child: const ColoredBox(color: Color(0x2E1F2329)),
                ),
              ),

            // 悬停播放按钮
            if (hoverSupported)
              Align(
                alignment: Alignment.center,
                child: AnimatedScale(
                  scale: _lifted ? 1 : 0.82,
                  duration: AppMotion.fast,
                  curve: AppMotion.standard,
                  child: AnimatedOpacity(
                    opacity: _lifted ? 1 : 0,
                    duration: AppMotion.fast,
                    child: IgnorePointer(
                      ignoring: !_lifted,
                      child: _PlayBadge(
                        onTap: widget.onPlay ?? widget.onTap,
                      ),
                    ),
                  ),
                ),
              ),

            // 左上角：榜单序号 / 来源角标
            if (widget.rank != null)
              Positioned(top: 8, left: 8, child: _RankBadge(rank: widget.rank!))
            else if ((widget.sourceBadge ?? '').isNotEmpty)
              Positioned(
                top: 8,
                left: 8,
                child: _Chip(text: widget.sourceBadge!),
              ),

            // 右上角：线路数量
            if (widget.showSourceCount && widget.movie.sources.isNotEmpty)
              Positioned(
                top: 8,
                right: 8,
                child: _Chip(
                  text: '${widget.movie.sources.length} 线路',
                  background: AppColors.accent,
                  foreground: AppColors.inkOnDark,
                ),
              ),

            // 底部：更新备注（无进度条时）
            if (widget.progress == null && (widget.movie.remarks ?? '').isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _RemarksLabel(text: widget.movie.remarks!),
              ),

            // 底部：继续观看进度
            if (widget.progress != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _ProgressBar(
                  value: widget.progress!.clamp(0.0, 1.0),
                  label: widget.progressLabel,
                ),
              ),

            // 发丝描边（置于最上层，保证在任何图片上都可见）
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(
                    color: _lifted ? AppColors.hairlineStrong : AppColors.hairline,
                    width: AppStroke.hairline,
                    strokeAlign: BorderSide.strokeAlignInside,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 文字区域 ────────────────────────────────────────────

  Widget _buildMeta() {
    final subtitle = widget.movie.displaySubtitle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.start,
      children: <Widget>[
        Text(
          widget.movie.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.posterTitle,
        ),
        const SizedBox(height: 2),
        Text(
          subtitle.isEmpty ? widget.movie.sourceName : subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.posterMeta,
        ),
      ],
    );
  }
}

// ── 内部小组件 ──────────────────────────────────────────────

class _PlayBadge extends StatelessWidget {
  const _PlayBadge({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.accent,
      shape: const CircleBorder(),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: const SizedBox(
          width: 42,
          height: 42,
          child: Icon(
            Icons.play_arrow_rounded,
            color: AppColors.inkOnDark,
            size: 24,
          ),
        ),
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final isTop = rank <= 3;
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isTop ? AppColors.accent : const Color(0xB31F2329),
        borderRadius: AppRadius.xsBR,
      ),
      child: Text(
        '$rank',
        style: AppTypography.badge.copyWith(fontSize: 11.5),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.text,
    this.background,
    this.foreground,
  });

  final String text;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background ?? const Color(0xA61F2329),
        borderRadius: AppRadius.xsBR,
      ),
      child: Text(
        text,
        style: AppTypography.badge.copyWith(color: foreground),
      ),
    );
  }
}

class _RemarksLabel extends StatelessWidget {
  const _RemarksLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 18, 8, 6),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Colors.transparent, Color(0xB3000000)],
        ),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: AppColors.inkOnDark,
        ),
      ),
    );
  }
}

/// 继续观看进度条：白色半透明槽 + 品牌色填充 + 文案。
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value, this.label});

  final double value;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Colors.transparent, Color(0xC7000000)],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if ((label ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
              child: Text(
                label!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppColors.inkOnDark,
                ),
              ),
            ),
          // 进度槽：3px 高，用 Row + flex 实现精确比例填充
          // （避免在不确定高度约束下使用 FractionallySizedBox）
          SizedBox(
            height: 3,
            child: Row(
              children: <Widget>[
                Expanded(
                  flex: (value * 1000).round().clamp(0, 1000),
                  child: const ColoredBox(color: AppColors.accent),
                ),
                Expanded(
                  flex: (1000 - value * 1000).round().clamp(0, 1000),
                  child: const ColoredBox(color: Color(0x40FFFFFF)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
