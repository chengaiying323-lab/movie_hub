import 'package:flutter/material.dart';

/// 播放层专属暗色令牌。
///
/// 为什么不复用 [AppColors]
/// ------------------------------------------------------------------
/// 需求明确要求：**无论全局是否浅色模式，播放层内部必须是半透明暗色**。
/// 这不是审美偏好，而是可读性刚需 —— 视频画面亮度不可控，
/// 浅色控件落在高光雪景/白墙镜头会彻底消失。因此播放层需要一套
/// **独立于主题**、永远为暗的色板。
///
/// 与浅色体系的对应关系（色相保持一致，明度反向）：
/// ```
/// 浅色主题                播放层
/// canvas  #F5F6F8   ←→    videoBackground #000000
/// surface #FFFFFF   ←→    panel           #14161A
/// ink     #1F2329   ←→    ink             #FFFFFF
/// accent  #E8543F   ←→    accent          #FF6B55（暗底提亮）
/// ```
///
/// 半透明而非纯色
/// ------------------------------------------------------------------
/// [scrimTop] / [scrimBottom] 都是带 alpha 的黑：控件区用渐变遮罩压暗画面，
/// 但**保留画面可见**。整块不透明黑条会把"在看视频"变成"在看字幕条"，
/// 失去沉浸感。alpha 取值经过实测：上 70%、下 80% 是"文字清晰"与
/// "画面可辨"的平衡点。
class PlayerPalette {
  const PlayerPalette._();

  // ── 画面底色 ────────────────────────────────────────────
  /// 视频区底色。纯黑让未铺满的 letterbox 区域不干扰注意力。
  static const Color videoBackground = Color(0xFF000000);

  // ── 覆盖层遮罩 ──────────────────────────────────────────
  /// 顶部遮罩（返回键 / 标题所在区域）。
  static const Color scrimTop = Color(0xB3000000); // 70%

  /// 底部遮罩（进度条 / 操作按钮所在区域）。
  static const Color scrimBottom = Color(0xCC000000); // 80%

  /// 遮罩中段的完全透明点。
  static const Color scrimClear = Color(0x00000000);

  static const LinearGradient topScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[scrimTop, scrimClear],
  );

  static const LinearGradient bottomScrim = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: <Color>[scrimBottom, scrimClear],
  );

  // ── 面板 / 抽屉 ────────────────────────────────────────
  /// 侧滑面板底色（高不透明度，保证长列表文字可读）。
  static const Color panel = Color(0xF214161A); // 95%

  /// 面板内浮起元素（选中项、卡片）。
  static const Color panelElevated = Color(0xFF1C2026);

  /// 面板内嵌入容器（分区块底）。
  static const Color panelSunken = Color(0xFF101215);

  /// 毛玻璃浮层底（配合 BackdropFilter）。
  static const Color frosted = Color(0xD9101114); // 85%

  // ── 文字 ────────────────────────────────────────────────
  static const Color ink = Color(0xFFFFFFFF);
  static const Color inkSecondary = Color(0xCCFFFFFF); // 80%
  static const Color inkTertiary = Color(0x8FFFFFFF); // 56%
  static const Color inkFaint = Color(0x5CFFFFFF); // 36%

  // ── 描边 ────────────────────────────────────────────────
  /// 暗底上的发丝线用白色低透明度，叠加在任何画面上都成立。
  static const Color hairline = Color(0x1FFFFFFF); // 12%
  static const Color hairlineStrong = Color(0x33FFFFFF); // 20%

  // ── 强调 / 语义色 ───────────────────────────────────────
  /// 与浅色主题同色相，但在暗底上提亮，否则珊瑚红会显得"脏"。
  static const Color accent = Color(0xFFFF6B55);
  static const Color accentSoft = Color(0x33FF6B55);

  static const Color danger = Color(0xFFFF6B6B);
  static const Color dangerSoft = Color(0x26FF6B6B);

  static const Color warning = Color(0xFFFFB84D);
  static const Color positive = Color(0xFF4ADE80);

  // ── 进度条 ──────────────────────────────────────────────
  /// 未播放轨道。
  static const Color track = Color(0x40FFFFFF); // 25%

  /// 已缓冲但未播放段。
  static const Color buffered = Color(0x73FFFFFF); // 45%

  /// 拖拽手柄。
  static const Color thumb = Color(0xFFFFFFFF);

  // ── 控件底 ──────────────────────────────────────────────
  /// 图标按钮底：半透明黑，让按钮在任意画面上都有一层"底衬"。
  static const Color controlBg = Color(0x59000000); // 35%
  static const Color controlBgHover = Color(0x8C000000); // 55%

  /// 顶部信息胶囊底。
  static const Color chipBg = Color(0x66000000); // 40%

  /// 列表项选中态底。
  static const Color selected = Color(0x1FFFFFFF); // 12%

  /// 面板拖拽把手。
  static const Color grabber = Color(0x4DFFFFFF); // 30%

  // ── 尺寸约定 ────────────────────────────────────────────
  /// 侧滑面板宽度上限（再宽会挤掉画面，失去"边看边选"的意义）。
  static const double sideSheetMaxWidth = 380;

  /// 侧滑面板占屏宽比例上限（移动端横屏）。
  static const double sideSheetWidthFactor = 0.82;
}
