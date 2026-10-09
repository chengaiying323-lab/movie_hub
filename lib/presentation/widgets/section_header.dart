import 'package:flutter/material.dart';

import '../../core/design/design.dart';

/// 分区标题。
///
/// 视觉：左侧 3×16 的品牌色圆角竖条 + 标题 + 可选副标题 + 右侧操作区。
/// 竖条是浅色极简风格中替代"大色块标题栏"的常见做法——
/// 用极小的面积提供视觉锚点，不破坏留白。
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.padding = EdgeInsets.zero,
    this.onTitleTap,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTitleTap;

  @override
  Widget build(BuildContext context) {
    final titleRow = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(title, style: AppTypography.sectionTitle),
        if (subtitle != null) ...<Widget>[
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.posterMeta,
            ),
          ),
        ],
      ],
    );

    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: onTitleTap == null
                ? titleRow
                : GestureDetector(
                    onTap: onTitleTap,
                    behavior: HitTestBehavior.opaque,
                    child: titleRow,
                  ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: AppSpacing.sm),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// 「更多」文字按钮（分区标题右侧）。
class SectionMoreButton extends StatefulWidget {
  const SectionMoreButton({super.key, this.label = '查看全部', this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  State<SectionMoreButton> createState() => _SectionMoreButtonState();
}

class _SectionMoreButtonState extends State<SectionMoreButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) return const SizedBox.shrink();

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMotion.instant,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xxs,
          ),
          decoration: BoxDecoration(
            color: _hovered ? AppColors.accentSofter : Colors.transparent,
            borderRadius: AppRadius.xsBR,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                widget.label,
                style: AppTypography.posterMeta.copyWith(
                  color: _hovered ? AppColors.accent : AppColors.inkTertiary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: _hovered ? AppColors.accent : AppColors.inkTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
