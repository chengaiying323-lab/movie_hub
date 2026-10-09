import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/player/player.dart';

/// 全局播放策略。
///
/// 默认取 [PlayerBootstrap] 在 `main()` 中生效的那份配置。
/// 单独开一个 Provider 的意义在于**可覆盖**：设置页想调大
/// `stallTimeout`、测试想关掉自动重试，只需 override 这一个节点。
final playerConfigProvider = Provider<PlayerEngineConfig>(
  (ref) => PlayerBootstrap.config,
);

/// 播放内核工厂。
///
/// 为什么是「工厂」而不是「一个内核实例」
/// ------------------------------------------------------------------
/// 内核持有原生解码器与渲染面（Windows 上是 D3D 纹理），是**重量级资源**，
/// 生命周期应当与播放页严格对齐：
/// * 页面进入 → 创建一个；
/// * 页面退出 → 销毁一个；
/// * 切换线路 / 选集 → **复用同一个**（重新 `open` 即可），
///   这样才能做到"无缝切换"——重建内核会有 300ms 级的黑屏。
///
/// 如果把它做成一个全局单例，就会同时引入两个问题：
/// 页面退出后资源不释放；以及将来做画中画/小窗预览时无法并存两个实例。
///
/// 做成工厂还有个附带好处：测试里 override 成返回 `FakePlayerEngine`
/// 的工厂，就能在没有原生库的环境下跑通整条播放页逻辑。
final playerEngineFactoryProvider = Provider<PlayerEngine Function()>((ref) {
  final config = ref.read(playerConfigProvider);
  return () => MediaKitPlayerEngine(config: config);
});
