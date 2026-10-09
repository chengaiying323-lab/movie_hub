import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/design.dart';
import '../../domain/entities/movie.dart';
import '../../domain/entities/watch_record.dart';
import '../providers/watch_history_providers.dart';
import 'app_menu.dart';

/// 执行一次观影状态变更，并统一处理成功 / 失败提示。
///
/// 为什么需要它：`WatchHistoryNotifier` 采用**乐观更新 + 失败回滚**，
/// 落盘失败时会把异常重新抛出。若调用方 `await` 后不处理，
/// 用户看到的将是"状态闪了一下又变回去，却没有任何解释"。
/// 这里把异常收敛成一条可读的失败提示。
///
/// [context] 只用于取 `ScaffoldMessenger`，在 await 之前捕获，
/// 因此不会触发 `use_build_context_synchronously`。
Future<void> runWatchAction(
  BuildContext context, {
  required Future<void> Function() action,
  required String successMessage,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  try {
    await action();
    messenger.showSnackBar(SnackBar(content: Text(successMessage)));
  } catch (error) {
    messenger.showSnackBar(SnackBar(content: Text('操作失败：$error')));
  }
}

/// 观影状态三态按钮（想看 / 正在看 / 已看）。
///
/// 交互设计
/// ------------------------------------------------------------------
/// 单击 → 弹出菜单，一次性给出三种状态与「移出片库」。
/// 为什么不做"单击轮换状态"？三种状态 + 移出共 4 种结果，
/// 轮换会让用户无法预测下一次点击的结果，也会误触丢记录。
///
/// 视觉上把状态编码进三处，保证一眼可辨：
/// 图标（书签 / 播放 / 对勾）+ 文案 + 底色与描边。
class WatchStatusButton extends ConsumerStatefulWidget {
  const WatchStatusButton({
    super.key,
    required this.movie,
    this.onChanged,
  });

  final Movie movie;

  /// 状态变更回调；`null` 表示条目已被移出片库。
  final void Function(WatchStatus? next)? onChanged;

  @override
  ConsumerState<WatchStatusButton> createState() => _WatchStatusButtonState();
}

class _WatchStatusButtonState extends ConsumerState<WatchStatusButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(watchStatusProvider(widget.movie.id));
    final active = status != null;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: _openMenu,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.standard,
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: active
                ? AppColors.accentSoft
                : (_hovered ? AppColors.surfaceMuted : AppColors.surface),
            borderRadius: AppRadius.smBR,
            border: Border.all(
              color: active ? AppColors.accent : AppColors.hairlineStrong,
              width: active ? AppStroke.emphasis : AppStroke.hairline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AnimatedSwitcher(
                duration: AppMotion.fast,
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: animation,
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: Icon(
                  _iconFor(status),
                  key: ValueKey<Object>(status ?? 'none'),
                  size: 17,
                  color: active ? AppColors.accent : AppColors.inkSecondary,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                _labelFor(status),
                style: AppTypography.button.copyWith(
                  fontSize: 13.5,
                  color: active ? AppColors.accent : AppColors.ink,
                ),
              ),
              const SizedBox(width: 3),
              Icon(
                Icons.expand_more_rounded,
                size: 16,
                color: active ? AppColors.accent : AppColors.inkTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openMenu() async {
    final notifier = ref.read(watchHistoryProvider.notifier);
    final status = ref.read(watchStatusProvider(widget.movie.id));

    final value = await AppMenu.showFor(
      context,
      globalPosition: _menuAnchor(),
      title: widget.movie.title,
      actions: <AppMenuAction>[
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
        if (status != null)
          const AppMenuAction(
            value: 'remove',
            label: '移出我的片库',
            icon: Icons.delete_outline_rounded,
            destructive: true,
          ),
      ],
    );

    if (!mounted || value == null) return;

    switch (value) {
      case 'want':
        await notifier.setStatus(widget.movie, WatchStatus.wantToWatch);
        widget.onChanged?.call(WatchStatus.wantToWatch);
      case 'unwant':
      case 'remove':
        await notifier.remove(widget.movie.id);
        widget.onChanged?.call(null);
      case 'watching':
        await notifier.markWatching(widget.movie);
        widget.onChanged?.call(WatchStatus.watching);
      case 'watched':
        await notifier.markWatched(widget.movie);
        widget.onChanged?.call(WatchStatus.watched);
    }
  }

  /// 菜单锚点：按钮右下角。
  ///
  /// 用挂载 RenderObject 的全局位置换算，避免在移动端出现坐标为 (0,0)
  /// 导致菜单飞到屏幕左上角。
  Offset _menuAnchor() {
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      return box.localToGlobal(Offset(box.size.width - 24, box.size.height));
    }
    final overlay = Overlay.of(context).context.findRenderObject();
    if (overlay is RenderBox) {
      return overlay.localToGlobal(overlay.size.center(Offset.zero));
    }
    return Offset.zero;
  }

  static IconData _iconFor(WatchStatus? status) {
    switch (status) {
      case WatchStatus.wantToWatch:
        return Icons.bookmarks_rounded;
      case WatchStatus.watching:
        return Icons.play_circle_filled_rounded;
      case WatchStatus.watched:
        return Icons.task_alt_rounded;
      case null:
        return Icons.bookmark_add_outlined;
    }
  }

  static String _labelFor(WatchStatus? status) {
    switch (status) {
      case WatchStatus.wantToWatch:
        return '想看';
      case WatchStatus.watching:
        return '正在看';
      case WatchStatus.watched:
        return '已看';
      case null:
        return '加入片库';
    }
  }
}
