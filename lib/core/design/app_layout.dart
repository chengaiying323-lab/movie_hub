import 'package:flutter/material.dart';

import 'app_spacing.dart';

/// 响应式布局计算。
///
/// 这是**跨平台适配的唯一判定源**：所有页面/组件都从这里取断点结果，
/// 禁止在页面内散落 `MediaQuery.sizeOf(context).width > 900` 这类判断。
///
/// 断点体系
/// ```
///  < 600          手机竖屏      2 列海报
///  600 ~ 900      手机横屏/小窗 3 列海报
///  900 ~ 1240     桌面窄窗      4 列海报 + 收拢导航栏
///  1240 ~ 1560    桌面标准      5 列海报 + 展开导航栏
///  ≥ 1560         桌面宽屏      6 列海报
/// ```
class AppLayout {
  const AppLayout._();

  /// 手机断点。
  static const double compact = 600;

  /// 桌面断点（切换导航形态：侧边栏 ↔ 底部栏）。
  static const double medium = 900;

  /// 桌面标准断点（侧边栏展开文字）。
  static const double expanded = 1240;

  /// 桌面宽屏断点。
  static const double large = 1560;

  /// 从 BuildContext 取布局结果。
  static AppLayoutData of(BuildContext context) =>
      AppLayoutData(MediaQuery.sizeOf(context).width);

  /// 从显式宽度构造（用于测试或特殊容器）。
  static AppLayoutData fromWidth(double width) => AppLayoutData(width);

  /// 页面内容水平内边距。
  static double pagePadding(double width) {
    if (width >= medium) return AppSpacing.pageHPaddingDesktop;
    if (width >= compact) return AppSpacing.lg;
    return AppSpacing.pageHPaddingMobile;
  }

  /// 海报网格列数。
  static int gridColumns(double width) {
    if (width >= large) return 6;
    if (width >= expanded) return 5;
    if (width >= medium) return 4;
    if (width >= compact) return 3;
    return 2;
  }
}

/// 布局计算结果（值对象，便于在 build 内缓存复用）。
@immutable
class AppLayoutData {
  const AppLayoutData(this.width);

  final double width;

  /// 移动端形态（底部导航栏）。
  bool get isCompact => width < AppLayout.medium;

  /// 桌面端形态（侧边导航栏）。
  bool get isDesktop => width >= AppLayout.medium;

  /// 侧边导航栏是否展开显示文字。
  bool get isExpandedRail => width >= AppLayout.expanded;

  /// 是否使用大尺寸 Banner。
  bool get isLargeScreen => width >= AppLayout.expanded;

  int get gridColumns => AppLayout.gridColumns(width);

  double get pagePadding => AppLayout.pagePadding(width);

  /// 横向滑动栏单屏可见卡片数量（决定是否显示左右滚动箭头）。
  int get rowVisibleCount {
    if (width < AppLayout.compact) return 2;
    if (width < AppLayout.medium) return 3;
    if (width < AppLayout.expanded) return 5;
    return 6;
  }

  /// 超宽屏下的内容最大宽度（居中，避免内容被无限拉伸）。
  double get maxContentWidth => width >= AppLayout.large ? 1680 : width;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AppLayoutData && other.width == width;

  @override
  int get hashCode => width.hashCode;
}
