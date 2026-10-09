import 'package:flutter/material.dart';

import '../../core/design/design.dart';
import 'frosted_surface.dart';

/// 导航目的地描述。
@immutable
class AppDestination {
  const AppDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badgeCount,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// 角标数量（如「我的」页的更新提醒）。
  final int? badgeCount;
}

/// 脚手架占位内边距。
///
/// 页面通过 `AppScaffoldInsets.bottomOf(context)` 获取底部导航栏占用的高度，
/// 并把它加到滚动区域的 `padding.bottom`。这样既能让内容"滚动到导航栏下方"
/// （毛玻璃才有可模糊的对象），又不会让最后一行内容被永久遮住。
class AppScaffoldInsets extends InheritedWidget {
  const AppScaffoldInsets({
    super.key,
    required this.bottom,
    this.top = 0,
    required super.child,
  });

  final double bottom;
  final double top;

  static AppScaffoldInsets? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScaffoldInsets>();

  static double bottomOf(BuildContext context) => maybeOf(context)?.bottom ?? 0;

  static double topOf(BuildContext context) => maybeOf(context)?.top ?? 0;

  @override
  bool updateShouldNotify(AppScaffoldInsets oldWidget) =>
      oldWidget.bottom != bottom || oldWidget.top != top;
}

/// 自适应脚手架（跨平台导航外壳）。
///
/// 两种形态
/// ------------------------------------------------------------------
/// | | 桌面端（≥900dp） | 移动端（<900dp） |
/// |---|---|---|
/// | 导航位置 | 左侧悬浮毛玻璃侧边栏 | 底部悬浮毛玻璃标签栏 |
/// | 侧边栏宽度 | 84dp（宽屏展开 208dp） | — |
/// | 安全区 | 无需特殊处理 | 顶部灵动岛 / 底部 Home 指示条 |
/// | 主体 | 与侧边栏并排 | 铺满，导航栏浮于其上 |
///
/// 注意：桌面端的侧边栏是**悬浮**的（四周留白 + 圆角 + 阴影），
/// 而非贴边的传统面板——这是浅色极简风格的关键细节。
class AdaptiveScaffold extends StatelessWidget {
  const AdaptiveScaffold({
    super.key,
    required this.body,
    required this.destinations,
    required this.currentIndex,
    required this.onDestinationSelected,
    this.brand,
    this.railFooter,
    this.background,
  });

  final Widget body;
  final List<AppDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;

  /// 侧边栏顶部品牌区。
  final Widget? brand;

  /// 侧边栏底部（如设置入口）。
  final Widget? railFooter;

  final Color? background;

  @override
  Widget build(BuildContext context) {
    final layout = AppLayout.of(context);
    return Scaffold(
      backgroundColor: background ?? AppColors.canvas,
      body: layout.isDesktop ? _buildDesktop(context, layout) : _buildMobile(context, layout),
    );
  }

  // ── 桌面端 ──────────────────────────────────────────────

  Widget _buildDesktop(BuildContext context, AppLayoutData layout) {
    final expanded = layout.isExpandedRail;
    final railWidth =
        expanded ? AppSizes.railWidthExpanded : AppSizes.railWidth;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(width: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: SizedBox(
            width: railWidth,
            child: _FloatingRail(
              destinations: destinations,
              currentIndex: currentIndex,
              onSelect: onDestinationSelected,
              expanded: expanded,
              brand: brand,
              footer: railFooter,
            ),
          ),
        ),
        Expanded(
          child: AppScaffoldInsets(
            bottom: 0,
            top: 0,
            child: body,
          ),
        ),
      ],
    );
  }

  // ── 移动端 ──────────────────────────────────────────────

  Widget _buildMobile(BuildContext context, AppLayoutData layout) {
    final mediaPadding = MediaQuery.paddingOf(context);
    final barHeight = AppSizes.bottomBarHeight;
    final margin = AppSizes.bottomBarMargin;

    // 内容需要为浮动标签栏让出的高度（含 Home 指示条安全区）
    final reserved =
        barHeight + margin * 2 + mediaPadding.bottom;

    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: AppScaffoldInsets(
            bottom: reserved,
            top: mediaPadding.top,
            child: body,
          ),
        ),
        // 仅底部让出安全区：顶部由各页面自己的 AppBar 处理
        Positioned(
          left: margin,
          right: margin,
          bottom: 0,
          child: SafeArea(
            top: false,
            // 这里**不能**用 const：margin 是运行时算出来的值
            // （其它地方的 EdgeInsets 都是常量令牌，所以能 const）。
            minimum: EdgeInsets.only(bottom: margin),
            child: _FloatingBottomBar(
              destinations: destinations,
              currentIndex: currentIndex,
              onSelect: onDestinationSelected,
            ),
          ),
        ),
      ],
    );
  }
}

// ── 悬浮侧边栏 ──────────────────────────────────────────────

class _FloatingRail extends StatelessWidget {
  const _FloatingRail({
    required this.destinations,
    required this.currentIndex,
    required this.onSelect,
    required this.expanded,
    this.brand,
    this.footer,
  });

  final List<AppDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final bool expanded;
  final Widget? brand;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return FrostedSurface(
      blur: 30,
      color: AppColors.surface.withOpacity(0.78),
      borderRadius: AppRadius.largeBR,
      border: Border.all(
        color: AppColors.hairline,
        width: AppStroke.hairline,
        strokeAlign: BorderSide.strokeAlignInside,
      ),
      boxShadow: AppShadows.frostedBar,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (brand != null) ...<Widget>[
            brand!,
            const SizedBox(height: AppSpacing.lg),
          ],
          for (var i = 0; i < destinations.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: AppSpacing.xxs),
            _RailItem(
              destination: destinations[i],
              selected: i == currentIndex,
              expanded: expanded,
              onTap: () => onSelect(i),
            ),
          ],
          const Spacer(),
          if (footer != null) footer!,
        ],
      ),
    );
  }
}

class _RailItem extends StatefulWidget {
  const _RailItem({
    required this.destination,
    required this.selected,
    required this.expanded,
    required this.onTap,
  });

  final AppDestination destination;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.destination;
    final selected = widget.selected;

    final icon = Icon(
      selected ? d.selectedIcon : d.icon,
      size: 21,
      color: selected
          ? AppColors.accent
          : (_hovered ? AppColors.inkSecondary : AppColors.inkTertiary),
    );

    Widget content = widget.expanded
        ? Row(
            children: <Widget>[
              icon,
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  d.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? AppColors.accent : AppColors.ink,
                  ),
                ),
              ),
              if (d.badgeCount != null && d.badgeCount! > 0)
                _Badge(count: d.badgeCount!),
            ],
          )
        : Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              icon,
              const SizedBox(height: 3),
              Text(
                d.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? AppColors.accent : AppColors.inkTertiary,
                ),
              ),
            ],
          );

    final item = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.standard,
          height: widget.expanded ? 44 : 56,
          padding: EdgeInsets.symmetric(
            horizontal: widget.expanded ? AppSpacing.sm : AppSpacing.xxs,
          ),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accentSoft
                : (_hovered ? AppColors.accentSofter : Colors.transparent),
            borderRadius: AppRadius.smBR,
          ),
          child: Center(child: content),
        ),
      ),
    );

    // 收起态只有图标，需要 Tooltip 兜底可读性
    return widget.expanded ? item : Tooltip(message: d.label, child: item);
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: AppTypography.badge.copyWith(fontSize: 9.5),
      ),
    );
  }
}

// ── 悬浮底部标签栏 ──────────────────────────────────────────

class _FloatingBottomBar extends StatelessWidget {
  const _FloatingBottomBar({
    required this.destinations,
    required this.currentIndex,
    required this.onSelect,
  });

  final List<AppDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return FrostedSurface(
      blur: 30,
      color: AppColors.frostedStrong,
      borderRadius: AppRadius.largeBR,
      border: Border.all(
        color: AppColors.hairline,
        width: AppStroke.hairline,
        strokeAlign: BorderSide.strokeAlignInside,
      ),
      boxShadow: AppShadows.overlay,
      height: AppSizes.bottomBarHeight,
      child: Row(
        children: <Widget>[
          for (var i = 0; i < destinations.length; i++)
            Expanded(
              child: _BottomItem(
                destination: destinations[i],
                selected: i == currentIndex,
                onTap: () => onSelect(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _BottomItem extends StatelessWidget {
  const _BottomItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final AppDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = destination;
    final color = selected ? AppColors.accent : AppColors.inkTertiary;

    return Semantics(
      selected: selected,
      button: true,
      label: d.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.smBR,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            AnimatedContainer(
              duration: AppMotion.fast,
              curve: AppMotion.standard,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              decoration: BoxDecoration(
                color: selected ? AppColors.accentSoft : Colors.transparent,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Icon(
                    selected ? d.selectedIcon : d.icon,
                    size: 21,
                    color: color,
                  ),
                  if (d.badgeCount != null && d.badgeCount! > 0)
                    Positioned(
                      right: -8,
                      top: -4,
                      child: _Badge(count: d.badgeCount!),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              d.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
