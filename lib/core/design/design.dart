/// 设计系统统一出口。
///
/// 页面与组件统一 `import '../core/design/design.dart';`，
/// 只依赖此处暴露的令牌，禁止在组件中硬编码色值 / 圆角 / 时长。
library;

export 'app_colors.dart';
export 'app_layout.dart';
export 'app_motion.dart';
export 'app_shadows.dart';
export 'app_spacing.dart';
export 'app_typography.dart';
