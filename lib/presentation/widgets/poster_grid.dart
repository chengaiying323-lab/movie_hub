import 'package:flutter/material.dart';

import '../../core/design/design.dart';
import 'shimmer.dart';

/// 海报网格度量（列数 / 单项宽度 / 单项高度）。
///
/// 为什么要显式计算而不是交给 `childAspectRatio`？
/// ------------------------------------------------------------------
/// 卡片结构是「海报（2:3）+ 固定高度文字区」。若用 `childAspectRatio`，
/// 文字区高度会随卡片宽度线性缩放，导致窄屏文字被压扁、宽屏出现大片空白。
/// 显式计算 `mainAxisExtent = itemWidth / (2/3) + 文字区高度` 可保证
/// **海报始终严格 2:3，文字区高度恒定**。
@immutable
class PosterGridMetrics {
  const PosterGridMetrics({
    required this.columns,
    required this.itemWidth,
    required this.itemExtent,
    required this.spacing,
  });

  final int columns;
  final double itemWidth;

  /// 卡片总高度 = 海报高度 + 文字区。
  final double itemExtent;

  final double spacing;

  /// 依据当前屏幕宽度解析。
  ///
  /// [availableWidth] 可传入嵌套容器的实际宽度（默认取「整屏 - 侧边栏」）；
  /// [columns] / [spacing] / [horizontalPadding] 可显式覆盖。
  factory PosterGridMetrics.resolve(
    BuildContext context, {
    double? availableWidth,
    int? columns,
    double? spacing,
    double? horizontalPadding,
  }) {
    final layout = AppLayout.of(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    // 侧边栏在宽屏会展开为 label 形态（208dp），估宽时必须一并扣除，
    // 否则宽屏下的列数会比实际多算一列。
    final railWidth = layout.isDesktop
        ? (layout.isExpandedRail
            ? AppSizes.railWidthExpanded
            : AppSizes.railWidth)
        : 0.0;
    final pagePadding = horizontalPadding ?? layout.pagePadding;
    final gap = spacing ?? AppSpacing.sm;

    final containerWidth = availableWidth ?? (screenWidth - railWidth);
    final contentWidth = containerWidth - pagePadding * 2;

    return PosterGridMetrics.forWidth(
      contentWidth,
      columns: columns ?? layout.gridColumns,
      spacing: gap,
    );
  }

  /// 从「内容区可用宽度」直接构造（用于测试或自定义容器）。
  factory PosterGridMetrics.forWidth(
    double contentWidth, {
    required int columns,
    double spacing = AppSpacing.sm,
  }) {
    final cols = columns.clamp(1, 12);
    final usable = contentWidth - spacing * (cols - 1);
    final itemWidth = usable <= 0 ? 120.0 : usable / cols;
    return PosterGridMetrics(
      columns: cols,
      itemWidth: itemWidth,
      itemExtent:
          itemWidth / AppSizes.posterAspectRatio + AppSizes.rowTextExtent,
      spacing: spacing,
    );
  }

  SliverGridDelegate get gridDelegate =>
      SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing + AppSpacing.xs,
        mainAxisExtent: itemExtent,
      );
}

/// 海报网格（Sliver 版本，供 CustomScrollView 使用）。
class SliverPosterGrid extends StatelessWidget {
  const SliverPosterGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.metrics,
    this.horizontalPadding,
    this.spacing,
    this.columns,
  });

  final int itemCount;
  final NullableIndexedWidgetBuilder itemBuilder;
  final PosterGridMetrics? metrics;
  final double? horizontalPadding;
  final double? spacing;
  final int? columns;

  @override
  Widget build(BuildContext context) {
    final resolved = metrics ??
        PosterGridMetrics.resolve(
          context,
          horizontalPadding: horizontalPadding,
          spacing: spacing,
          columns: columns,
        );
    final padding = horizontalPadding ?? AppLayout.of(context).pagePadding;

    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: padding),
      sliver: SliverGrid(
        gridDelegate: resolved.gridDelegate,
        delegate: SliverChildBuilderDelegate(
          itemBuilder,
          childCount: itemCount,
          addAutomaticKeepAlives: false,
        ),
      ),
    );
  }
}

/// 海报网格（Box 版本，供 Column 内的固定区域使用）。
class PosterGrid extends StatelessWidget {
  const PosterGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.metrics,
    this.horizontalPadding,
    this.columns,
    this.spacing,
    this.shrinkWrap = true,
  });

  final int itemCount;
  final NullableIndexedWidgetBuilder itemBuilder;
  final PosterGridMetrics? metrics;
  final double? horizontalPadding;
  final int? columns;
  final double? spacing;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final resolved = metrics ??
        PosterGridMetrics.resolve(
          context,
          horizontalPadding: horizontalPadding,
          spacing: spacing,
          columns: columns,
        );

    return GridView.builder(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding ?? AppLayout.of(context).pagePadding,
      ),
      gridDelegate: resolved.gridDelegate,
      itemCount: itemCount,
      itemBuilder: itemBuilder,
    );
  }
}

/// 网格加载骨架（数量与列数对齐，保证首屏到内容的过渡不跳动）。
class SliverPosterSkeletonGrid extends StatelessWidget {
  const SliverPosterSkeletonGrid({
    super.key,
    this.count = 12,
    this.metrics,
    this.horizontalPadding,
    this.columns,
  });

  final int count;
  final PosterGridMetrics? metrics;
  final double? horizontalPadding;
  final int? columns;

  @override
  Widget build(BuildContext context) {
    final resolved =
        metrics ?? PosterGridMetrics.resolve(context, columns: columns);
    final padding = horizontalPadding ?? AppLayout.of(context).pagePadding;

    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: padding),
      sliver: SliverGrid(
        gridDelegate: resolved.gridDelegate,
        delegate: SliverChildBuilderDelegate(
          (_, __) => const PosterSkeleton(),
          childCount: count,
        ),
      ),
    );
  }
}
