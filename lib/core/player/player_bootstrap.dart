import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import 'player_config.dart';

/// 播放内核的全局初始化生命周期。
///
/// 时序要求
/// ------------------------------------------------------------------
/// `MediaKit.ensureInitialized()` **必须在 `runApp()` 之前、且在任何
/// `Player` / `VideoController` 构造之前**执行。原因：它会去加载
/// 各平台的原生库（Windows 是 `libmpv-2.dll` 全家桶，iOS/Android 是
/// 打包进 framework 的静态库），并注册平台通道；晚于 `Player` 构造
/// 会直接抛"native library not found"。
///
/// 因此正确的调用位置是 `main.dart`：
/// ```dart
/// Future<void> main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await Future.wait(<Future<void>>[
///     PlayerBootstrap.ensureInitialized(),
///     WatchHistoryLocalDataSource.initialize(),
///   ]);
///   runApp(const ProviderScope(child: MovieHubApp()));
/// }
/// ```
///
/// 为什么不在这里预热一个引擎实例
/// ------------------------------------------------------------------
/// `VideoController` 的构造会立刻创建原生渲染面（Windows 上是 D3D 纹理，
/// iOS 上是 Metal 纹理 —— media_kit 在 iOS 走的是 libmpv/MPVKit 而非
/// AVPlayerLayer），预热等于"开应用就占一份解码资源"。
/// 而真正的收益只是省下几十毫秒 —— 播放页本身还有网络请求要走，
/// 这点时间被完全掩盖。**用复杂度换不到可感知的收益，就不做。**
///
/// 释放
/// ------------------------------------------------------------------
/// 应用级单例内核没有"统一的销毁时机"（Windows 关窗、iOS 进后台都可能是
/// 进程被挂起而非正常退出），因此**不做全局 shutdown**：
/// 每个播放页在 `dispose` 里销毁自己持有的引擎，进程退出时由系统回收。
/// 这样也天然支持"多实例"——将来做画中画 / 小窗预览时不需要改造。
class PlayerBootstrap {
  const PlayerBootstrap._();

  static bool _initialized = false;
  static PlayerEngineConfig _config = const PlayerEngineConfig();

  /// 内核是否已就绪。
  static bool get isInitialized => _initialized;

  /// 全局生效的内核配置。业务侧（如设置页）可据此调整策略。
  static PlayerEngineConfig get config => _config;

  /// 初始化播放内核。幂等，可重复调用。
  ///
  /// [config] 只在首次调用时生效；重复调用不会覆盖已生效的配置，
  /// 避免"某个页面顺手调了一次"把全局策略改掉。
  static Future<void> ensureInitialized({
    PlayerEngineConfig config = const PlayerEngineConfig(),
  }) async {
    if (_initialized) return;

    _config = config;
    MediaKit.ensureInitialized();
    _initialized = true;

    debugPrint('[PlayerBootstrap] 内核就绪 · $environmentLabel');
  }

  /// 环境摘要（供「关于 / 诊断」页与问题反馈使用）。
  ///
  /// 把"用户以为的播放失败"和"环境事实"分开呈现，
  /// 能省掉大量"我这边播不了"却查不出原因的支持成本。
  static String get environmentLabel {
    final platform = switch (defaultTargetPlatform) {
      TargetPlatform.windows => 'Windows · libmpv',
      TargetPlatform.iOS => 'iOS · libmpv(MPVKit)',
      TargetPlatform.android => 'Android · libmpv',
      TargetPlatform.macOS => 'macOS · libmpv',
      TargetPlatform.linux => 'Linux · libmpv',
      TargetPlatform.fuchsia => 'Fuchsia · libmpv',
    };
    final hwdec = _config.hardwareAcceleration ? '硬解优先' : '软解';
    return '$platform · $hwdec · 重试 ${_config.maxRetryAttempts} 次';
  }
}
