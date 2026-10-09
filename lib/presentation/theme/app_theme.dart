import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/design/design.dart';

/// 浅色极简主题（Light Minimalist Theme）。
///
/// 设计意图
/// ------------------------------------------------------------------
/// - **底色温润**：页面底色 `#F5F6F8`，纯白仅保留给卡片，消除大面积高反差；
/// - **层级靠描边与微阴影**，而非靠色块深浅——这是极简风格的通用做法；
/// - **去除 M3 的 surfaceTint 染色**：Material 3 默认会把主色混入所有表面，
///   在浅色极简语境下会产生难以控制的偏色，故全局置为透明；
/// - **动效克制**：全局时长与曲线来自 [AppMotion]，不使用夸张弹性曲线。
///
/// 本应用**仅提供浅色模式**（产品决策）：强制 `Brightness.light`，
/// 不响应系统深色设置，避免出现两套需要分别打磨的视觉体系。
class AppTheme {
  const AppTheme._();

  /// 全局 Light ThemeData。
  static ThemeData get light {
    final scheme = _colorScheme();
    final textTheme = AppTypography.textTheme;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      textTheme: textTheme,

      // 页面底色：温润米白灰（注意不是 ColorScheme.surface）
      scaffoldBackgroundColor: AppColors.canvas,
      canvasColor: AppColors.canvas,
      dividerColor: AppColors.hairlineSubtle,

      // 水波纹与悬停底色统一走极淡的品牌色，避免默认灰蓝色出戏
      splashFactory: InkRipple.splashFactory,
      splashColor: AppColors.accentSofter,
      highlightColor: AppColors.accentSofter,
      hoverColor: AppColors.accentSofter,

      visualDensity: VisualDensity.standard,

      // ── 应用栏 ───────────────────────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: const IconThemeData(
          color: AppColors.inkSecondary,
          size: 20,
        ),
        actionsIconTheme: const IconThemeData(
          color: AppColors.inkSecondary,
          size: 20,
        ),
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),

      // ── 卡片：唯一纯白层级 ───────────────────────────────
      cardTheme: CardTheme(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: AppColors.shadow,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardBR,
          side: const BorderSide(
            color: AppColors.hairline,
            width: AppStroke.hairline,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
        ),
      ),

      // ── 输入框 ───────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(color: AppColors.inkTertiary),
        border: const OutlineInputBorder(
          borderRadius: AppRadius.pillBR,
          borderSide: BorderSide(
            color: AppColors.hairline,
            width: AppStroke.hairline,
          ),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: AppRadius.pillBR,
          borderSide: BorderSide(
            color: AppColors.hairline,
            width: AppStroke.hairline,
          ),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: AppRadius.pillBR,
          borderSide: BorderSide(
            color: AppColors.accent,
            width: AppStroke.emphasis,
          ),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: AppRadius.pillBR,
          borderSide: BorderSide(color: AppColors.danger),
        ),
      ),

      // ── 标签 ─────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.accentSoft,
        disabledColor: AppColors.surfaceMuted,
        side: const BorderSide(
          color: AppColors.hairline,
          width: AppStroke.hairline,
        ),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.xsBR),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: 0,
        ),
        labelStyle: textTheme.labelMedium ?? const TextStyle(),
        secondaryLabelStyle: textTheme.labelMedium ?? const TextStyle(),
        showCheckmark: false,
        elevation: 0,
        pressElevation: 0,
      ),

      // ── 按钮 ─────────────────────────────────────────────

      /// 主按钮：实心品牌色（柔和珊瑚红），不使用高饱和填充。
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.inkOnDark,
          disabledBackgroundColor: AppColors.surfaceMuted,
          disabledForegroundColor: AppColors.inkDisabled,
          minimumSize: const Size(0, 42),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.smBR),
          textStyle: AppTypography.button,
          elevation: 0,
        ),
      ),

      /// 次按钮：描边式，最贴合极简风格。
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          backgroundColor: AppColors.surface,
          minimumSize: const Size(0, 42),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          side: const BorderSide(
            color: AppColors.hairlineStrong,
            width: AppStroke.hairline,
          ),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.smBR),
          textStyle: AppTypography.button,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.inkSecondary,
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.smBR),
          textStyle: AppTypography.button,
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.inkSecondary,
          highlightColor: AppColors.accentSofter,
          minimumSize: const Size(AppSizes.touchTarget, AppSizes.touchTarget),
        ),
      ),

      // ── 导航 ─────────────────────────────────────────────

      /// 移动端底部导航栏：实际由自适应脚手架自定义毛玻璃容器承载，
      /// 此处样式作为兜底，保证第三方组件调用 NavigationBar 时不出戏。
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.frostedStrong,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.accentSoft,
        elevation: 0,
        height: AppSizes.bottomBarHeight,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppTypography.posterTitle.copyWith(color: AppColors.accent)
              : AppTypography.posterMeta,
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected)
                ? AppColors.accent
                : AppColors.inkTertiary,
          ),
        ),
      ),

      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: AppColors.accentSoft,
        elevation: 0,
        selectedLabelTextStyle:
            AppTypography.posterTitle.copyWith(color: AppColors.accent),
        unselectedLabelTextStyle: AppTypography.posterMeta,
        selectedIconTheme:
            const IconThemeData(color: AppColors.accent, size: 22),
        unselectedIconTheme:
            const IconThemeData(color: AppColors.inkTertiary, size: 22),
      ),

      // ── 反馈组件 ─────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.ink,
        contentTextStyle: const TextStyle(
          color: AppColors.inkOnDark,
          fontSize: 13.5,
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.smBR),
        insetPadding: const EdgeInsets.all(AppSpacing.md),
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.ink,
          borderRadius: AppRadius.xsBR,
        ),
        textStyle: const TextStyle(color: AppColors.inkOnDark, fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        waitDuration: const Duration(milliseconds: 500),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accent,
        linearTrackColor: AppColors.surfaceSunken,
        circularTrackColor: Colors.transparent,
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: AppColors.surface,
        elevation: 0,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.large),
          ),
        ),
      ),

      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.inkTertiary,
        textColor: AppColors.ink,
        contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.hairlineSubtle,
        thickness: AppStroke.hairline,
        space: AppStroke.hairline,
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.smBR,
          side: const BorderSide(
            color: AppColors.hairline,
            width: AppStroke.hairline,
          ),
        ),
        textStyle: const TextStyle(fontSize: 13.5, color: AppColors.ink),
      ),

      // 页面转场：桌面端使用克制的淡入上移，iOS 保留原生滑动返回手势
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
    );
  }

  /// 构造语义化 ColorScheme。
  ///
  /// 在 `fromSeed` 基础上覆盖关键角色，避免 M3 自动算法
  /// 在浅色模式下生成过饱和的强调色。
  static ColorScheme _colorScheme() {
    return ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.accent,
      onPrimary: AppColors.inkOnDark,
      primaryContainer: AppColors.accentSoft,
      onPrimaryContainer: AppColors.accent,
      secondary: AppColors.inkSecondary,
      onSecondary: AppColors.inkOnDark,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      surfaceTint: Colors.transparent,
      onSurfaceVariant: AppColors.inkSecondary,
      outline: AppColors.hairlineStrong,
      outlineVariant: AppColors.hairline,
      error: AppColors.danger,
      onError: AppColors.inkOnDark,
      errorContainer: AppColors.dangerSoft,
      shadow: AppColors.shadow,
      scrim: const Color(0x331F2329),
    );
  }

  /// 便捷入口，减少 `Theme.of(context).colorScheme` 的重复书写。
  static ColorScheme schemeOf(BuildContext context) =>
      Theme.of(context).colorScheme;

  static TextTheme textOf(BuildContext context) => Theme.of(context).textTheme;
}
