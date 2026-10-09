import 'package:flutter/material.dart';

import '../../core/design/design.dart';
import 'shimmer.dart';

/// 通用图片组件（海报 / 剧照 / 头像）。
///
/// 统一处理三态：
/// 1. **加载中** → 淡灰骨架屏（与卡片内容同尺寸，避免布局跳动）；
/// 2. **加载完成** → 淡入过渡（避免图片"啪"地出现）；
/// 3. **加载失败** → 低饱和度极简占位图（渐变底 + 线性图标 + 标题）。
///
/// 说明：第二阶段使用 `Image.network` + Flutter 内建缓存；
/// 第三阶段建议替换为 `cached_network_image` 以获得磁盘级 LRU 缓存
/// （影视海报的重复加载率极高，磁盘缓存可显著降低流量与首图延迟）。
class PosterImage extends StatelessWidget {
  const PosterImage({
    super.key,
    required this.url,
    required this.title,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.placeholderIcon = Icons.movie_outlined,
    this.fadeIn = true,
    this.skeletonOnly = false,
  });

  /// 图片地址；为空或加载失败时降级为占位图。
  final String? url;

  /// 占位图上显示的标题（帮助用户在无图时仍能识别内容）。
  final String title;

  final BoxFit fit;
  final AlignmentGeometry alignment;
  final IconData placeholderIcon;

  /// 是否使用淡入过渡。
  final bool fadeIn;

  /// 仅显示骨架（如已知资源尚未就绪时）。
  final bool skeletonOnly;

  bool get _hasUrl => (url ?? '').trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (skeletonOnly || !_hasUrl) {
      return skeletonOnly ? const _ImageSkeleton() : _Placeholder(
        title: title,
        icon: placeholderIcon,
      );
    }

    return Image.network(
      url!,
      fit: fit,
      alignment: alignment,
      // 源站图片普遍存在防盗链，失败时静默降级
      errorBuilder: (_, __, ___) =>
          _Placeholder(title: title, icon: placeholderIcon),
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || !fadeIn) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: AppMotion.normal,
          curve: AppMotion.standard,
          child: child,
        );
      },
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const _ImageSkeleton();
      },
    );
  }
}

/// 加载中骨架：与父容器同尺寸，确保不产生布局跳动。
class _ImageSkeleton extends StatelessWidget {
  const _ImageSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Shimmer(
      child: ColoredBox(
        color: AppColors.skeletonBase,
        child: SizedBox.expand(),
      ),
    );
  }
}

/// 低饱和度极简占位图。
///
/// 采用"极浅灰渐变 + 描边图标 + 底部标题"三段式，
/// 刻意保持低对比度，使其在浅色页面中"存在但不抢眼"。
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: AppColors.posterPlaceholderGradient,
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 24, color: AppColors.inkDisabled),
              if (title.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  title,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.3,
                    color: AppColors.inkTertiary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
