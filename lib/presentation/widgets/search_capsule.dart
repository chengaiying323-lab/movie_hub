import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/design/design.dart';

/// 轻质圆角搜索胶囊。
///
/// 视觉：全圆角（pill）+ 纯白底 + 发丝描边；聚焦时描边转为品牌色并
/// 附加极淡的品牌色光晕，不改变尺寸（避免聚焦瞬间的布局抖动）。
///
/// 桌面端额外提供 `Ctrl/Cmd + K` 聚焦、`Esc` 清空的键盘快捷方式
/// （由 [SearchShortcutScope] 统一拦截）。
class SearchCapsule extends StatefulWidget {
  const SearchCapsule({
    super.key,
    required this.controller,
    required this.focusNode,
    this.onSubmitted,
    this.onChanged,
    this.onClear,
    this.hint = '搜索影片、演员或导演',
    this.autofocus = false,
    this.showShortcutHint = true,
    this.height = 44,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;
  final String hint;
  final bool autofocus;

  /// 桌面端显示 `Ctrl K` 快捷键提示。
  final bool showShortcutHint;

  final double height;

  @override
  State<SearchCapsule> createState() => _SearchCapsuleState();
}

class _SearchCapsuleState extends State<SearchCapsule> {
  bool _focused = false;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocusChange);
    super.dispose();
  }

  void _handleFocusChange() {
    if (_focused == widget.focusNode.hasFocus) return;
    setState(() => _focused = widget.focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final layout = AppLayout.of(context);
    final hasText = widget.controller.text.isNotEmpty;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.standard,
        height: widget.height,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.pillBR,
          border: Border.all(
            color: _focused
                ? AppColors.accent
                : (_hovered ? AppColors.hairlineStrong : AppColors.hairline),
            width: _focused ? AppStroke.emphasis : AppStroke.hairline,
          ),
          boxShadow: _focused
              ? AppShadows.tinted(AppColors.accent, opacity: 0.14)
              : AppShadows.card,
        ),
        child: Row(
          children: <Widget>[
            const SizedBox(width: AppSpacing.md),
            Icon(
              Icons.search_rounded,
              size: 19,
              color: _focused ? AppColors.accent : AppColors.inkTertiary,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                autofocus: widget.autofocus,
                textInputAction: TextInputAction.search,
                onSubmitted: widget.onSubmitted,
                onChanged: (value) {
                  widget.onChanged?.call(value);
                  // 驱动清除按钮的显隐
                  setState(() {});
                },
                cursorColor: AppColors.accent,
                cursorWidth: 1.4,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.ink,
                  height: 1.2,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintText: widget.hint,
                  hintStyle: const TextStyle(
                    fontSize: 14,
                    color: AppColors.inkTertiary,
                  ),
                ),
              ),
            ),
            // 清除按钮 / 快捷键提示
            AnimatedSwitcher(
              duration: AppMotion.fast,
              child: hasText
                  ? _IconAction(
                      key: const ValueKey<String>('clear'),
                      icon: Icons.close_rounded,
                      tooltip: '清空',
                      onTap: () {
                        widget.controller.clear();
                        widget.onClear?.call();
                        setState(() {});
                      },
                    )
                  : (widget.showShortcutHint && layout.isDesktop
                      ? const Padding(
                          key: ValueKey<String>('hint'),
                          padding: EdgeInsets.only(right: AppSpacing.sm),
                          child: _ShortcutHint(),
                        )
                      : const SizedBox(
                          key: ValueKey<String>('none'),
                          width: AppSpacing.sm,
                        )),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      iconSize: 16,
      color: AppColors.inkTertiary,
      splashRadius: 16,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      padding: EdgeInsets.zero,
      tooltip: tooltip,
    );
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs),
      child: button,
    );
  }
}

/// `Ctrl K` 快捷键提示标签（纯视觉，实际拦截在 [SearchShortcutScope]）。
class _ShortcutHint extends StatelessWidget {
  const _ShortcutHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: AppRadius.xsBR,
      ),
      child: const Text(
        'Ctrl K',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w500,
          color: AppColors.inkTertiary,
        ),
      ),
    );
  }
}

/// 键盘快捷方式作用域。
///
/// - `Ctrl/Cmd + K` 或 `/` → 聚焦搜索框
/// - `Esc` → 失焦并清空
///
/// 仅桌面端生效（移动端无物理键盘，接入外接键盘时同样可用）。
class SearchShortcutScope extends StatelessWidget {
  const SearchShortcutScope({
    super.key,
    required this.focusNode,
    required this.onEscape,
    required this.child,
  });

  final FocusNode focusNode;
  final VoidCallback onEscape;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            focusNode.requestFocus,
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            focusNode.requestFocus,
        const SingleActivator(LogicalKeyboardKey.slash): focusNode.requestFocus,
        const SingleActivator(LogicalKeyboardKey.escape): () {
          focusNode.unfocus();
          onEscape();
        },
      },
      child: Focus(
        // 让页面根节点持有初始焦点：Flutter 的快捷键事件从"主焦点"向上冒泡，
        // 若整页都没有可聚焦节点，CallbackShortcuts 将收不到任何按键。
        autofocus: true,
        skipTraversal: true,
        child: child,
      ),
    );
  }
}
