import 'package:flutter/material.dart';

import '../../core/design/design.dart';

/// 骨架屏流光容器（Light Shimmer Effect）。
///
/// 实现方式：`ShaderMask` + 移动的线性渐变。
/// - `BlendMode.srcATop` 保证流光**只绘制在子节点的非透明区域**，
///   因此不需要为每种骨架形状单独设计动画，任意子节点都能获得流光；
/// - 子节点自身的颜色必须是 [AppColors.skeletonBase]（骨架底色），
///   流光才会以"提亮"的方式叠加，而不是替换成渐变本身。
///
/// 不使用任何第三方 shimmer 包：这段逻辑约 40 行，自研可避免引入依赖，
/// 也便于与设计令牌（底色 / 高光色 / 时长）保持一致。
class Shimmer extends StatefulWidget {
  const Shimmer({
    super.key,
    required this.child,
    this.enabled = true,
    this.period = AppMotion.shimmer,
  });

  final Widget child;

  /// 关闭后直接透传子节点（用于"减少动态效果"无障碍设置）。
  final bool enabled;

  final Duration period;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.period,
  );

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant Shimmer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.enabled && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // 流光带从左向右横扫：begin/end 同步平移，跨度 3 倍宽度以获得
        // "扫过后留白"的节奏感，而不是连续不断地闪。
        final t = _controller.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment(-1.6 + 3.2 * t, -0.3),
              end: Alignment(-0.6 + 3.2 * t, 0.3),
              colors: const <Color>[
                AppColors.skeletonBase,
                AppColors.skeletonHighlight,
                AppColors.skeletonBase,
              ],
              stops: const <double>[0.30, 0.50, 0.70],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// 骨架块：圆角矩形占位。
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius = AppRadius.xsBR,
    this.shape = BoxShape.rectangle,
  });

  final double? width;
  final double? height;
  final BorderRadius borderRadius;
  final BoxShape shape;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.skeletonBase,
        shape: shape,
        borderRadius: shape == BoxShape.circle ? null : borderRadius,
      ),
    );
  }
}

/// 海报骨架卡片：与真实海报卡片结构一致（海报 + 标题 + 副标题）。
///
/// 结构一致性很重要——骨架与真实内容尺寸不一致会产生明显的布局跳动（CLS）。
class PosterSkeleton extends StatelessWidget {
  const PosterSkeleton({super.key, this.showMeta = true});

  /// 是否渲染标题/副标题占位行。
  final bool showMeta;

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: AppColors.skeletonBase,
                borderRadius: AppRadius.cardBR,
              ),
            ),
          ),
          if (showMeta) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            const SkeletonBox(width: 92, height: 11),
            const SizedBox(height: AppSpacing.xxs),
            const SkeletonBox(width: 56, height: 9),
          ],
        ],
      ),
    );
  }
}

/// 文本行骨架（用于详情页简介等长文本块）。
class TextBlockSkeleton extends StatelessWidget {
  const TextBlockSkeleton({
    super.key,
    this.lines = 3,
    this.lineHeight = 12,
    this.spacing = AppSpacing.xs,
  });

  final int lines;
  final double lineHeight;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (var i = 0; i < lines; i++) ...<Widget>[
            if (i > 0) SizedBox(height: spacing),
            SkeletonBox(
              // 最后一行短一些，模拟真实段落
              width: i == lines - 1 ? 160 : double.infinity,
              height: lineHeight,
            ),
          ],
        ],
      ),
    );
  }
}
