import 'package:flutter/material.dart';

/// 动效令牌：时长与曲线。
///
/// 极简风格对动效的要求是"快、轻、无感"——用户不应注意到动画本身，
/// 只应感觉到界面"跟手"。因此：
/// - 时长普遍偏短（120~420ms），超过 400ms 会显得拖沓；
/// - 曲线统一使用 `easeOutCubic` 族，出场快、收尾缓，符合物理直觉；
/// - 禁止使用 `Curves.elasticOut` 这类夸张弹性曲线。
class AppMotion {
  const AppMotion._();

  // ── 时长 ────────────────────────────────────────────────

  /// 即时反馈：颜色变化、图标切换。
  static const Duration instant = Duration(milliseconds: 120);

  /// 快速：悬停、按压、标签切换。
  static const Duration fast = Duration(milliseconds: 180);

  /// 常规：卡片浮起、面板展开、路由内容淡入。
  static const Duration normal = Duration(milliseconds: 260);

  /// 慢速：页面转场、大面积布局变化（桌面端窗口缩放）。
  static const Duration slow = Duration(milliseconds: 420);

  /// 骨架屏流光循环周期。
  static const Duration shimmer = Duration(milliseconds: 1400);

  /// Banner 自动轮播间隔。
  static const Duration bannerAutoPlay = Duration(seconds: 6);

  // ── 曲线 ────────────────────────────────────────────────

  /// 标准曲线：绝大多数动效使用。
  static const Curve standard = Curves.easeOutCubic;

  /// 强调曲线：用于需要"利落收尾"的展开/收起。
  static const Curve emphasized = Curves.easeOutQuint;

  /// 柔和曲线：用于双向过渡（如淡入淡出、颜色插值）。
  static const Curve soft = Curves.easeInOutCubic;

  /// 减速曲线：用于从屏幕外滑入的元素。
  static const Curve decelerate = Curves.decelerate;

  // ── 位移量 ──────────────────────────────────────────────

  /// 卡片悬停浮起高度（逻辑像素）。
  static const double hoverLift = 4;

  /// 列表项悬停位移。
  static const double hoverNudge = 2;

  /// 按压下沉量。
  static const double pressSink = 1;
}

/// 预设的动画时长-曲线组合，避免各处重复书写。
class AppTransition {
  const AppTransition._();

  static const Duration duration = AppMotion.normal;
  static const Curve curve = AppMotion.standard;

  /// 标准补间（用于 AnimatedContainer / AnimatedOpacity 等）。
  static const Duration fast = AppMotion.fast;
  static const Duration instant = AppMotion.instant;

  /// 页面路由过渡：淡入 + 轻微上移，比平台默认更克制。
  static Route<T> fadeThrough<T>(Widget page, {String? name}) {
    return PageRouteBuilder<T>(
      settings: RouteSettings(name: name),
      transitionDuration: AppMotion.normal,
      reverseTransitionDuration: AppMotion.fast,
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: AppMotion.standard,
          reverseCurve: AppMotion.soft,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.012),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }
}
