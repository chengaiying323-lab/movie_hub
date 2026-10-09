import 'package:flutter/material.dart';

import 'core/constants/app_constants.dart';
import 'core/design/design.dart';
import 'presentation/pages/home_page.dart';
import 'presentation/theme/app_theme.dart';

/// 应用根组件。
///
/// 三项全局决策：
/// 1. **浅色模式固定**：`themeMode: ThemeMode.light` —— 本应用仅提供
///    浅色极简视觉体系（产品决策），不响应系统深色设置，
///    避免出现两套需要分别打磨的视觉；
/// 2. **字号缩放钳制**：把系统字号缩放限制在 0.9~1.25，
///    避免超大字号下海报网格与悬浮导航栏布局崩坏；
/// 3. **统一过渡**：页面转场由 [AppTheme] 的 `pageTransitionsTheme` 决定，
///    配合 `AppTransition.fadeThrough` 形成一致的克制观感。
class MovieHubApp extends StatelessWidget {
  const MovieHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      // 仅浅色模式：显式固定，不跟随系统深色
      themeMode: ThemeMode.light,
      home: const HomePage(),
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();

        final media = MediaQuery.of(context);
        final scale = media.textScaler.clamp(
          minScaleFactor: 0.9,
          maxScaleFactor: 1.25,
        );

        return MediaQuery(
          data: media.copyWith(textScaler: scale),
          child: ColoredBox(
            // 桌面端窗口边缘可能露出底色，统一填页面底色避免白边
            color: AppColors.canvas,
            child: child,
          ),
        );
      },
    );
  }
}
