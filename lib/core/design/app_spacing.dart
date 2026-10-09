import 'package:flutter/material.dart';

/// 尺寸令牌：间距 / 圆角 / 描边宽度 / 固定高度。
///
/// 全部使用 4pt 栅格，避免出现 7px、13px 这类不可控数值。
class AppSpacing {
  const AppSpacing._();

  /// 4pt 栅格基础单位。
  static const double unit = 4;

  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  /// 页面内容水平内边距（移动端 16 / 桌面端 32）。
  static const double pageHPaddingMobile = 16;
  static const double pageHPaddingDesktop = 32;

  /// 内容区最大宽度（超宽屏下避免内容被无限拉伸）。
  static const double contentMaxWidth = 1680;
}

/// 圆角令牌。
class AppRadius {
  const AppRadius._();

  /// 小圆角：标签、徽标。
  static const double xs = 6;

  /// 中圆角：按钮、输入框、选集按钮。
  static const double sm = 10;

  /// 卡片圆角：海报卡片、信息卡（需求指定 12~14，统一取 14）。
  static const double card = 14;

  /// 容器圆角：面板、Banner。
  static const double panel = 18;

  /// 大圆角：毛玻璃浮层。
  static const double large = 22;

  /// 胶囊（搜索框、浮动底栏）。
  static const double pill = 999;

  // ── 预置 BorderRadius ──────────────────────────────────

  static const BorderRadius cardBR = BorderRadius.all(Radius.circular(card));
  static const BorderRadius panelBR = BorderRadius.all(Radius.circular(panel));
  static const BorderRadius largeBR = BorderRadius.all(Radius.circular(large));
  static const BorderRadius smBR = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius xsBR = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius pillBR = BorderRadius.all(Radius.circular(pill));
}

/// 描边宽度令牌。
class AppStroke {
  const AppStroke._();

  /// 发丝线：视觉 0.5px。Flutter 逻辑像素下限为 1，
  /// 因此通过"1px 低透明度"模拟，而非真的用 0.5。
  static const double hairline = 0.8;

  /// 常规边框。
  static const double regular = 1;

  /// 选中态强调边框。
  static const double emphasis = 1.4;
}

/// 组件固定尺寸。
class AppSizes {
  const AppSizes._();

  /// 海报标准纵横比 2:3（需求指定）。
  static const double posterAspectRatio = 2 / 3;

  /// 桌面端侧边导航栏宽度（收拢态，仅图标）。
  static const double railWidth = 84;

  /// 侧边导航栏展开宽度（宽屏时显示文字）。
  static const double railWidthExpanded = 208;

  /// 展开导航栏的触发宽度。
  static const double railExpandBreakpoint = 1240;

  /// 顶部按钮 / 图标按钮命中区域。
  static const double touchTarget = 40;

  /// 移动端底部导航栏高度（不含安全区）。
  static const double bottomBarHeight = 62;

  /// 移动端底部导航栏外边距（悬浮式）。
  static const double bottomBarMargin = 12;

  /// Banner 高度。
  static const double bannerHeightDesktop = 340;
  static const double bannerHeightMobile = 216;

  /// 横向滑动栏高度 = 海报高度 + 文字区。
  static const double rowTextExtent = 46;

  /// 骨架屏单个海报高度（用于懒加载占位）。
  static const double skeletonPosterWidth = 160;
}
