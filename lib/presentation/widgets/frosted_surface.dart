import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/design/design.dart';

/// 毛玻璃容器（Frosted Glass Surface）。
///
/// 实现要点
/// ------------------------------------------------------------------
/// 1. 必须置于 **ClipRRect 内部**，否则 `BackdropFilter` 会采样整屏并在
///    圆角外产生溢出模糊。
/// 2. 只对**身后的内容**做模糊——因此容器自身需要一层半透明白色填充，
///    否则模糊结果会过暗（直接把背景色拉进来看起来像磨砂玻璃脏了）。
/// 3. 提供 [enabled] 开关：部分低端 Windows 设备上 `BackdropFilter` 会
///    显著增加 GPU 合成开销，此时可整体降级为不透明面板。
class FrostedSurface extends StatelessWidget {
  const FrostedSurface({
    super.key,
    required this.child,
    this.blur = 28,
    this.color = AppColors.frosted,
    this.borderRadius = BorderRadius.zero,
    this.border,
    this.boxShadow,
    this.enabled = true,
    this.padding,
    this.width,
    this.height,
  });

  /// 全局模糊开关（可在外层根据设备性能动态关闭）。
  static bool blurEnabled = true;

  final Widget child;

  /// 模糊强度（sigma）。建议 20~32：过低看不清磨砂感，过高会让背景糊成一片。
  final double blur;

  /// 底层半透明白色填充色。
  final Color color;

  final BorderRadius borderRadius;
  final Border? border;
  final List<BoxShadow>? boxShadow;
  final bool enabled;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final useBlur = enabled && blurEnabled && blur > 0;

    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: borderRadius,
        border: border,
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );

    if (useBlur) {
      surface = ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: surface,
        ),
      );
    }

    if (boxShadow != null && boxShadow!.isNotEmpty) {
      surface = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: boxShadow,
        ),
        child: surface,
      );
    }

    if (width != null || height != null) {
      surface = SizedBox(width: width, height: height, child: surface);
    }

    return surface;
  }
}

/// 极弱的毛玻璃（用于内容区顶部的滚动吸附标题栏）。
///
/// 与 [FrostedSurface] 的区别：更低的不透明度，让背后的海报隐约可见，
/// 形成"内容在玻璃下方流动"的层次感。
class SubtleFrostedBar extends StatelessWidget {
  const SubtleFrostedBar({
    super.key,
    required this.child,
    this.blur = 20,
    this.opacity = 0.72,
    this.borderRadius = BorderRadius.zero,
    this.border,
  });

  final Widget child;
  final double blur;
  final double opacity;
  final BorderRadius borderRadius;
  final Border? border;

  @override
  Widget build(BuildContext context) {
    return FrostedSurface(
      blur: blur,
      color: AppColors.surface.withOpacity(opacity),
      borderRadius: borderRadius,
      border: border,
      child: child,
    );
  }
}
