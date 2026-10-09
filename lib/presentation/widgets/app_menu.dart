import 'package:flutter/material.dart';

import '../../core/design/design.dart';

/// 快捷菜单项。
@immutable
class AppMenuAction {
  const AppMenuAction({
    required this.value,
    required this.label,
    required this.icon,
    this.destructive = false,
    this.enabled = true,
  });

  final String value;
  final String label;
  final IconData icon;

  /// 危险操作（删除类）：文字使用警示色。
  final bool destructive;

  final bool enabled;
}

/// 跨平台快捷菜单。
///
/// 交互约定
/// ------------------------------------------------------------------
/// | 平台 | 触发方式 | 呈现 |
/// |---|---|---|
/// | 桌面端（键鼠） | 鼠标右键 | 光标位置的浮出菜单 |
/// | 移动端（触控） | 长按 | 底部动作面板（拇指可达） |
///
/// 统一入口 [showFor] 自动按平台选择，调用方无需分支判断。
class AppMenu {
  const AppMenu._();

  /// 按平台自动选择呈现方式。
  static Future<String?> showFor(
    BuildContext context, {
    required Offset globalPosition,
    required List<AppMenuAction> actions,
    String? title,
  }) {
    final isDesktop = AppLayout.of(context).isDesktop;
    if (isDesktop) {
      return showContextMenu(
        context,
        globalPosition: globalPosition,
        actions: actions,
      );
    }
    return showActionSheet(context, actions: actions, title: title);
  }

  /// 桌面端：光标位置浮出菜单。
  static Future<String?> showContextMenu(
    BuildContext context, {
    required Offset globalPosition,
    required List<AppMenuAction> actions,
    String? title,
  }) {
    final overlay = Overlay.of(context).context.findRenderObject();
    if (overlay is! RenderBox) return Future<String?>.value();

    // 把全局坐标换算为相对 overlay 的矩形，并做边缘吸附——
    // 靠近屏幕右侧/底部时菜单会自动向左/上翻转，不会溢出屏幕。
    final position = RelativeRect.fromRect(
      Rect.fromPoints(globalPosition, globalPosition),
      Offset.zero & overlay.size,
    );

    return showMenu<String>(
      context: context,
      position: position,
      color: AppColors.surface,
      elevation: 0,
      items: <PopupMenuEntry<String>>[
        if (title != null)
          PopupMenuItem<String>(
            enabled: false,
            height: 34,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.posterMeta,
            ),
          ),
        if (title != null) const PopupMenuDivider(height: 1),
        for (final action in actions)
          PopupMenuItem<String>(
            value: action.value,
            enabled: action.enabled,
            height: 40,
            child: Row(
              children: <Widget>[
                Icon(
                  action.icon,
                  size: 17,
                  color: action.destructive
                      ? AppColors.danger
                      : AppColors.inkTertiary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  action.label,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: action.destructive ? AppColors.danger : AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
      ],
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadius.smBR,
        side: BorderSide(
          color: AppColors.hairline,
          width: AppStroke.hairline,
        ),
      ),
    );
  }

  /// 移动端：底部动作面板，符合拇指可达区域。
  static Future<String?> showActionSheet(
    BuildContext context, {
    required List<AppMenuAction> actions,
    String? title,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.large),
        ),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (title != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    0,
                    AppSpacing.md,
                    AppSpacing.xs,
                  ),
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.posterTitle,
                  ),
                ),
              for (final action in actions)
                ListTile(
                  enabled: action.enabled,
                  leading: Icon(
                    action.icon,
                    size: 20,
                    color: action.destructive
                        ? AppColors.danger
                        : AppColors.inkTertiary,
                  ),
                  title: Text(
                    action.label,
                    style: TextStyle(
                      fontSize: 14.5,
                      color:
                          action.destructive ? AppColors.danger : AppColors.ink,
                    ),
                  ),
                  onTap: action.enabled
                      ? () => Navigator.of(sheetContext).pop(action.value)
                      : null,
                ),
              const SizedBox(height: AppSpacing.xs),
            ],
          ),
        );
      },
    );
  }
}

/// 便捷写法：把 [Offset] 与动作列表绑定，供 `onSecondaryTapDown` 直接调用。
extension AppMenuGesture on Widget {
  /// 为任意组件附加「右键 / 长按」快捷菜单。
  Widget withAppMenu({
    required List<AppMenuAction> Function() actionsBuilder,
    String? Function()? titleBuilder,
    void Function(String value)? onSelected,
  }) {
    return _MenuHost(
      actionsBuilder: actionsBuilder,
      titleBuilder: titleBuilder,
      onSelected: onSelected,
      child: this,
    );
  }
}

class _MenuHost extends StatelessWidget {
  const _MenuHost({
    required this.child,
    required this.actionsBuilder,
    this.titleBuilder,
    this.onSelected,
  });

  final Widget child;
  final List<AppMenuAction> Function() actionsBuilder;
  final String? Function()? titleBuilder;
  final void Function(String value)? onSelected;

  Future<void> _open(BuildContext context, Offset position) async {
    final value = await AppMenu.showFor(
      context,
      globalPosition: position,
      actions: actionsBuilder(),
      title: titleBuilder?.call(),
    );
    if (value != null) onSelected?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) => _open(context, details.globalPosition),
      onLongPressStart: (details) => _open(context, details.globalPosition),
      child: child,
    );
  }
}
