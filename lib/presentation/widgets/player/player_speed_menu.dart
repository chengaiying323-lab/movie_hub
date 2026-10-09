import 'package:flutter/material.dart';

import '../../../core/design/design.dart';
import '../../../core/player/player_config.dart';
import '../../theme/player_palette.dart';

/// 倍速选择菜单（0.5x / 1.0x / 1.25x / 1.5x / 2.0x）。
///
/// 用锚定弹出菜单而不是常驻一排按钮：播放层底部空间极其有限，
/// 而倍速属于"偶尔调一次"的低频操作，常驻会挤占选集/线路这些高频入口。
///
/// 菜单项文案刻意显示成 `1.0x` 而非 `正常`：用户调倍速时脑子里
/// 想的就是数值，给数值比给形容词更省一次翻译。
class PlayerSpeedMenu {
  const PlayerSpeedMenu._();

  /// 档位与展示文案。
  ///
  /// 用 `static final` 而不是 `static const`：这个映射的键是 `double`，
  /// 在云端工具链上以 const 形式出现时被常量求值器拒绝
  /// （`Not a constant expression` / `Constant evaluation error`）。
  /// 去掉 `const` 后它退化成普通的 map 字面量 —— 非 const 字面量不要求
  /// 元素为编译期常量，语义完全不变，只是不再参与编译期规范化。
  /// 这个表只在弹出菜单时查几次，没有任何性能影响。
  static final Map<double, String> _labels = <double, String>{
    0.5: '0.5x 慢放',
    1.0: '1.0x 正常',
    1.25: '1.25x 稍快',
    1.5: '1.5x 快放',
    2.0: '2.0x 极速',
  };

  /// 在 [anchorKey] 所在控件下方弹出菜单。
  ///
  /// 返回用户选中的倍速；取消返回 null。
  static Future<double?> show(
    BuildContext context, {
    required GlobalKey anchorKey,
    required double current,
  }) {
    final overlay = Overlay.of(context).context.findRenderObject();
    final anchorBox = anchorKey.currentContext?.findRenderObject();
    if (overlay is! RenderBox || anchorBox is! RenderBox) {
      return Future<double?>.value();
    }

    // 把锚点控件的矩形换算到 overlay 坐标系，交给 showMenu 做边缘吸附。
    final topLeft = anchorBox.localToGlobal(Offset.zero, ancestor: overlay);
    final bottomRight = anchorBox.localToGlobal(
      anchorBox.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );

    return showMenu<double>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(topLeft, bottomRight),
        Offset.zero & overlay.size,
      ),
      color: PlayerPalette.panelElevated,
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.smBR,
        side: BorderSide(
          color: PlayerPalette.hairline,
          width: AppStroke.hairline,
        ),
      ),
      items: <PopupMenuEntry<double>>[
        for (final option in PlayerEngineConfig.speedOptions)
          PopupMenuItem<double>(
            value: option,
            height: 42,
            child: _SpeedItem(
              label: _labels[option] ?? '${option}x',
              selected: (option - current).abs() < 0.001,
            ),
          ),
      ],
    );
  }
}

class _SpeedItem extends StatelessWidget {
  const _SpeedItem({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 20,
          child: selected
              ? const Icon(
                  Icons.check_rounded,
                  size: 16,
                  color: PlayerPalette.accent,
                )
              : null,
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? PlayerPalette.ink : PlayerPalette.inkSecondary,
          ),
        ),
      ],
    );
  }
}
