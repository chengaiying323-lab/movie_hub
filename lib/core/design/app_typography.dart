import 'package:flutter/material.dart';

import 'app_colors.dart';

/// 字体与排版令牌。
///
/// 不打包自定义字体：iOS 使用 SF Pro，Windows 使用 Segoe UI，
/// 两者都是各自平台最优的中英混排字体，显式指定反而会退化。
/// 因此仅调整字号 / 字重 / 行高 / 字距。
class AppTypography {
  const AppTypography._();

  /// 中文正文行高比英文需要更大（1.55 起步），否则密排阅读吃力。
  static const double _bodyHeight = 1.55;
  static const double _titleHeight = 1.3;

  /// 用于 Banner / 大标题的字距收紧（视觉更紧密精致）。
  static const double _tightLetterSpacing = -0.2;

  static TextTheme get textTheme => const TextTheme(
        // ── 展示级 ────────────────────────────────────────
        displaySmall: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w700,
          height: _titleHeight,
          letterSpacing: _tightLetterSpacing,
          color: AppColors.ink,
        ),

        // ── 标题级 ────────────────────────────────────────
        headlineMedium: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          height: _titleHeight,
          letterSpacing: _tightLetterSpacing,
          color: AppColors.ink,
        ),
        // 这两个样式被页面直接引用（`AppTypography.headlineSmall` / `.titleMedium`），
        // 因此在这里引用下面具名的静态常量，保证「主题里的样式」与
        // 「页面直接用的样式」永远是同一个定义，不会各自漂移。
        headlineSmall: headlineSmall,
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          height: _titleHeight,
          color: AppColors.ink,
        ),
        titleMedium: titleMedium,
        titleSmall: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: _titleHeight,
          color: AppColors.ink,
        ),

        // ── 正文级 ────────────────────────────────────────
        bodyLarge: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          height: _bodyHeight,
          color: AppColors.ink,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          height: _bodyHeight,
          color: AppColors.inkSecondary,
        ),
        bodySmall: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          height: _bodyHeight,
          color: AppColors.inkSecondary,
        ),

        // ── 辅助级 ────────────────────────────────────────
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: 1.2,
          color: AppColors.ink,
        ),
        labelMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          height: 1.2,
          color: AppColors.inkSecondary,
        ),
        labelSmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w400,
          height: 1.2,
          color: AppColors.inkTertiary,
        ),
      );

  // ── 语义化样式快捷入口 ──────────────────────────────────
  // 避免各处写 `style: Theme.of(context).textTheme.xxx?.copyWith(...)`
  //
  // 约定：凡是**被页面/组件直接引用**的样式，都必须在这里具名。
  // 这样"搜一下这个样式名"就能找到全部使用点，而不必去读
  // textTheme 的字面量数值再全局比对。

  /// 页面大标题（发现页 / 片库页 / 数据源页的页头）。
  static const TextStyle headlineSmall = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: _titleHeight,
    letterSpacing: _tightLetterSpacing,
    color: AppColors.ink,
  );

  /// 区块 / 弹窗标题。
  static const TextStyle titleMedium = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: _titleHeight,
    color: AppColors.ink,
  );

  /// 海报卡片标题（单行省略）。
  static const TextStyle posterTitle = TextStyle(
    fontSize: 13.5,
    fontWeight: FontWeight.w600,
    height: 1.25,
    color: AppColors.ink,
  );

  /// 海报卡片副标题（年份 / 备注）。
  static const TextStyle posterMeta = TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w400,
    height: 1.25,
    color: AppColors.inkTertiary,
  );

  /// 分区标题（首页各推荐栏）。
  static const TextStyle sectionTitle = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: _tightLetterSpacing,
    color: AppColors.ink,
  );

  /// 角标文字。
  static const TextStyle badge = TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w600,
    height: 1.1,
    color: AppColors.inkOnDark,
  );

  /// 详情页大标题。
  static const TextStyle detailTitle = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 1.25,
    letterSpacing: _tightLetterSpacing,
    color: AppColors.ink,
  );

  /// 按钮文字。
  static const TextStyle button = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  /// 选集按钮文字。
  static const TextStyle episode = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
    height: 1.2,
  );
}
