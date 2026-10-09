import 'package:flutter/material.dart';

import '../../core/design/design.dart';

/// 统一的二次确认弹窗。
///
/// 为什么所有破坏性操作都要走这里：
/// 「移出记录」「清空历史」都不可撤销，而它们与「继续播放」共用同一个点击热区
/// —— 一次误触就会丢数据。统一封装还能保证确认语气与视觉一致。
///
/// 返回 `true` 表示用户确认；点击遮罩 / 取消 / 返回键均返回 `false`。
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '确定',
  String cancelLabel = '取消',
  bool destructive = false,
  IconData? icon,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: const Color(0x3D1F2329),
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadius.panelBR,
          side: BorderSide(
            color: AppColors.hairline,
            width: AppStroke.hairline,
          ),
        ),
        titlePadding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.xs,
        ),
        contentPadding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.sm,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        title: Row(
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(
                icon,
                size: 19,
                color: destructive ? AppColors.danger : AppColors.accent,
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
            Expanded(
              child: Text(
                title,
                style: AppTypography.titleMedium,
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(
            fontSize: 13.5,
            height: 1.65,
            color: AppColors.inkSecondary,
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              cancelLabel,
              style: const TextStyle(color: AppColors.inkSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor:
                  destructive ? AppColors.danger : AppColors.accent,
            ),
            child: Text(
              confirmLabel,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: destructive ? AppColors.danger : AppColors.accent,
              ),
            ),
          ),
        ],
      );
    },
  );
  return result ?? false;
}
