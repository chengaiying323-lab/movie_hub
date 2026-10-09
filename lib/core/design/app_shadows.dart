import 'package:flutter/material.dart';

import 'app_colors.dart';

/// 阴影令牌：极轻的弥散阴影（Soft Diffuse Shadow）。
///
/// 浅色极简的关键在于**阴影要"几乎看不见但能感知"**：
/// - 使用低透明度（4%~10%）而非夸张的黑色投影；
/// - 使用大 blurRadius + 小 offset，形成"光晕"而非"硬边投影"；
/// - 多层叠加（近距离小阴影 + 远距离大阴影）模拟真实环境光。
///
/// 注意：浅色模式下阴影不能替代描边——两者叠加使用，
/// 描边保证边缘清晰，阴影保证层级的"悬浮感"。
class AppShadows {
  const AppShadows._();

  /// 静止态卡片：几乎不可见，仅提供极弱的层级提示。
  static const List<BoxShadow> card = <BoxShadow>[
    BoxShadow(
      color: Color(0x0A1F2329), // 4%
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
    BoxShadow(
      color: Color(0x081F2329), // 3%
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];

  /// 悬停态卡片：浮起 4px，阴影扩散（配合位移形成"微浮起"）。
  static const List<BoxShadow> cardHover = <BoxShadow>[
    BoxShadow(
      color: Color(0x141F2329), // 8%
      blurRadius: 6,
      offset: Offset(0, 4),
    ),
    BoxShadow(
      color: Color(0x0F1F2329), // 6%
      blurRadius: 24,
      offset: Offset(0, 10),
    ),
  ];

  /// 按压态：比静止更收敛（形成"按下"的物理反馈）。
  static const List<BoxShadow> cardPressed = <BoxShadow>[
    BoxShadow(
      color: Color(0x081F2329),
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
  ];

  /// 浮层 / 下拉菜单 / 模态面板。
  static const List<BoxShadow> overlay = <BoxShadow>[
    BoxShadow(
      color: Color(0x1A1F2329), // 10%
      blurRadius: 8,
      offset: Offset(0, 4),
    ),
    BoxShadow(
      color: Color(0x141F2329), // 8%
      blurRadius: 40,
      offset: Offset(0, 16),
    ),
  ];

  /// 毛玻璃导航栏：向内容区方向的单向投影。
  static const List<BoxShadow> frostedBar = <BoxShadow>[
    BoxShadow(
      color: Color(0x0F1F2329),
      blurRadius: 20,
      offset: Offset(0, 4),
    ),
  ];

  /// 主按钮：带品牌色的柔和投影。
  static const List<BoxShadow> accentButton = <BoxShadow>[
    BoxShadow(
      color: Color(0x33E8543F), // 20% 主色
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];

  /// Banner 上的文字可读性确保层。
  static const List<BoxShadow> textOnImage = <BoxShadow>[
    BoxShadow(
      color: Color(0x4D000000),
      blurRadius: 12,
      offset: Offset(0, 2),
    ),
  ];

  /// 快捷工具：以主色生成同色系投影。
  static List<BoxShadow> tinted(Color color, {double opacity = 0.22}) {
    return <BoxShadow>[
      BoxShadow(
        color: color.withOpacity(opacity),
        blurRadius: 14,
        offset: const Offset(0, 5),
      ),
    ];
  }

  /// 主色阴影（默认取品牌色）。
  static List<BoxShadow> get brand => tinted(AppColors.accent);
}
