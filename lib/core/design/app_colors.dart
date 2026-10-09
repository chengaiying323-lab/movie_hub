import 'package:flutter/material.dart';

/// 浅色极简色板（Light Minimalist Palette）。
///
/// 设计约束
/// ------------------------------------------------------------------
/// 1. **纯白 `#FFFFFF` 只用于卡片层级**，承载"内容单元"的心智；
///    页面主底色使用米白/浅灰，避免大面积高反差造成的视觉疲劳。
/// 2. 边框统一使用 **8% 黑**（约 #14000000）而非实色灰，
///    保证叠加在任何底色上都呈现一致的"极细发丝线"观感。
/// 3. 所有强调色降低饱和度，避免在浅底上产生刺眼的色块。
///
/// 层级模型（由低到高）：
/// ```
/// canvas  页面底色      #F5F6F8
/// surfaceMuted 次级容器  #EFF1F4   （骨架屏底、输入框、标签）
/// surface 卡片          #FFFFFF   （唯一纯白）
/// elevated 浮层/毛玻璃   #FFFFFF @ 72%
/// ```
class AppColors {
  const AppColors._();

  // ── 背景层级 ────────────────────────────────────────────

  /// 页面主底色：温润米白灰，长时间浏览不刺眼。
  static const Color canvas = Color(0xFFF5F6F8);

  /// 略暖的备用底色（用于需要轻微区分的区域，如 Banner 渐变落点）。
  static const Color canvasWarm = Color(0xFFF7F8FA);

  /// 卡片 / 内容单元底色（全局唯一纯白）。
  static const Color surface = Color(0xFFFFFFFF);

  /// 次级容器：输入框、标签底、骨架屏基底、选中态底色。
  static const Color surfaceMuted = Color(0xFFEFF1F4);

  /// 更深一级的凹陷容器（如进度槽、分隔块）。
  static const Color surfaceSunken = Color(0xFFE8EAEE);

  /// 毛玻璃浮层底色（需配合 BackdropFilter 使用）。
  static const Color frosted = Color(0xB8FFFFFF); // 72% 白

  /// 毛玻璃浮层底色的高不透明度版本（移动端底部栏，保证文字可读）。
  static const Color frostedStrong = Color(0xD9FFFFFF); // 85% 白

  // ── 描边 ────────────────────────────────────────────────

  /// 极细发丝线（0.5px 视觉）：卡片边框、分隔线。
  static const Color hairline = Color(0x14000000); // 8%

  /// 稍强描边：输入框边框、选中态轮廓。
  static const Color hairlineStrong = Color(0x1F000000); // 12%

  /// 更弱的分隔线（列表项之间）。
  static const Color hairlineSubtle = Color(0x0D000000); // 5%

  // ── 文字 ────────────────────────────────────────────────

  /// 主文字：近黑但保留一点冷调，避免纯黑的生硬感。
  static const Color ink = Color(0xFF1F2329);

  /// 次级文字：元数据、副标题。
  static const Color inkSecondary = Color(0xFF646A73);

  /// 三级文字：提示、占位、时间戳。
  static const Color inkTertiary = Color(0xFF8F959E);

  /// 禁用态文字。
  static const Color inkDisabled = Color(0xFFBBBFC4);

  /// 深色底上的反白文字（海报角标、Banner 标题）。
  static const Color inkOnDark = Color(0xFFFFFFFF);

  // ── 强调色 ──────────────────────────────────────────────

  /// 品牌主色：柔和珊瑚红，温度感强但在浅底上不刺眼。
  static const Color accent = Color(0xFFE8543F);

  /// 主色按压态。
  static const Color accentPressed = Color(0xFFD1442F);

  /// 主色淡背景（选中标签底、图标底）。
  static const Color accentSoft = Color(0x14E8543F); // 8%

  /// 主色更淡背景（悬停态）。
  static const Color accentSofter = Color(0x0AE8543F); // 4%

  /// 辅助色：用于"已追剧""已完成"等正向状态。
  static const Color positive = Color(0xFF3FA46A);
  static const Color positiveSoft = Color(0x143FA46A);

  /// 警示色（校验失败、源不可达）。
  static const Color danger = Color(0xFFD9463F);
  static const Color dangerSoft = Color(0x14D9463F);

  /// 提醒色（降级状态）。
  static const Color warning = Color(0xFFD98A2B);
  static const Color warningSoft = Color(0x14D98A2B);

  // ── 骨架屏 ──────────────────────────────────────────────

  /// 骨架屏基底色（与 surfaceMuted 同族，略浅）。
  static const Color skeletonBase = Color(0xFFECEEF1);

  /// 骨架屏流光高光色。
  static const Color skeletonHighlight = Color(0xFFF9FAFB);

  // ── 阴影 ────────────────────────────────────────────────

  /// 阴影基色：极低透明度的冷灰，而非纯黑。
  static const Color shadow = Color(0xFF1F2329);

  /// 海报占位图的低饱和渐变（加载失败时使用）。
  static const List<Color> posterPlaceholderGradient = <Color>[
    Color(0xFFEDEFF2),
    Color(0xFFE3E6EB),
  ];

  /// 图片未加载时的遮罩色（覆盖在海报上方的浅灰蒙层）。
  static const Color imageScrim = Color(0x0F1F2329);
}
