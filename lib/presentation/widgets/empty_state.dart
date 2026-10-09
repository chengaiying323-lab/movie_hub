import 'package:flutter/material.dart';

import '../../core/design/design.dart';

/// 极简空态 / 错误态。
///
/// 视觉规范：不使用大面积插画，仅"线性图标 + 主标题 + 说明 + 单一操作"。
/// 低饱和度的图标底色让空态在浅色页面中不显得突兀。
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.action,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? description;
  final Widget? action;

  /// 紧凑模式：用于行内（如横向栏内）而非整页。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: compact ? 44 : 60,
          height: compact ? 44 : 60,
          decoration: const BoxDecoration(
            color: AppColors.surfaceMuted,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: compact ? 20 : 26,
            color: AppColors.inkTertiary,
          ),
        ),
        SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
        Text(
          title,
          textAlign: TextAlign.center,
          style: AppTypography.sectionTitle.copyWith(
            fontSize: compact ? 14 : 15.5,
          ),
        ),
        if (description != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Text(
              description!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.6,
                color: AppColors.inkTertiary,
              ),
            ),
          ),
        ],
        if (action != null) ...<Widget>[
          SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
          action!,
        ],
      ],
    );

    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.xl),
        child: content,
      ),
    );
  }
}

/// 错误态（网络失败 / 解析失败），带重试。
class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    required this.message,
    this.onRetry,
    this.title = '出了点问题',
    this.compact = false,
  });

  final String message;
  final VoidCallback? onRetry;
  final String title;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.cloud_off_outlined,
      title: title,
      description: message,
      compact: compact,
      action: onRetry == null
          ? null
          : OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重试'),
            ),
    );
  }
}

/// 分区级空态（首页某个推荐栏没有数据时，在栏内占位而非整页空态）。
class SectionEmpty extends StatelessWidget {
  const SectionEmpty({super.key, this.message = '该分类暂无内容'});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 96,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardBR,
        border: Border.fromBorderSide(
          BorderSide(color: AppColors.hairline, width: AppStroke.hairline),
        ),
      ),
      child: Text(
        message,
        style: const TextStyle(fontSize: 12.5, color: AppColors.inkTertiary),
      ),
    );
  }
}
