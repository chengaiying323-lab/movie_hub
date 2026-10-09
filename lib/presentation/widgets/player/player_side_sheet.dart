import 'package:flutter/material.dart';

import '../../../core/design/design.dart';
import '../../theme/player_palette.dart';

/// 播放层通用侧滑面板（选集 / 线路切换共用）。
///
/// 为什么用侧滑面板而不是底部弹窗
/// ------------------------------------------------------------------
/// 播放场景的形态与普通页面不同：
/// * **横屏时屏幕高度很小**，底部弹窗要么盖住半个画面，要么内容区被压到
///   只能显示 2~3 行；
/// * 用户的心理预期是"**边看边选**" —— 面板出现时画面仍在播放且可见，
///   所以面板必须窄、贴边，遮罩也要足够淡。
///
/// 因此统一：右侧滑入、宽度 `min(380, 屏宽 × 0.82)`、遮罩 40% 黑。
///
/// 返回值即用户的选择（`null` 表示取消）。抽屉内容和盘托出，
/// **不碰任何播放逻辑** —— 拿到返回值后怎么切，由播放页决定。
Future<T?> showPlayerSideSheet<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required Widget child,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: title,
    barrierColor: const Color(0x66000000),
    transitionDuration: AppMotion.normal,
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (dialogContext, animation, _, __) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppMotion.emphasized,
        reverseCurve: AppMotion.soft,
      );
      return Align(
        alignment: Alignment.centerRight,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: SizedBox(
            width: playerSideSheetWidth(MediaQuery.sizeOf(dialogContext).width),
            height: double.infinity,
            child: ColoredBox(
              color: PlayerPalette.panel,
              child: SafeArea(
                left: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    PlayerPanelHeader(title: title, subtitle: subtitle),
                    Expanded(child: child),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// 面板宽度：窄屏按比例，宽屏封顶。
double playerSideSheetWidth(double screenWidth) {
  final proportional = screenWidth * PlayerPalette.sideSheetWidthFactor;
  return proportional < PlayerPalette.sideSheetMaxWidth
      ? proportional
      : PlayerPalette.sideSheetMaxWidth;
}

/// 面板标题栏。
///
/// 额外动作（如线路抽屉的"重新测速"）由调用方作为顶部内容放进 [child]，
/// 而不是塞进本组件 —— 否则每加一个动作就要改一次公共签名。
class PlayerPanelHeader extends StatelessWidget {
  const PlayerPanelHeader({
    super.key,
    required this.title,
    this.subtitle,
  });

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xxs,
        AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: PlayerPalette.ink,
                  ),
                ),
                if (subtitle != null && subtitle!.trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: PlayerPalette.inkTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            iconSize: 20,
            color: PlayerPalette.inkSecondary,
            splashRadius: 20,
            tooltip: '关闭',
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}
