import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/constants/app_constants.dart';
import 'core/player/player.dart';
import 'data/datasources/local/watch_history_local_datasource.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 两项初始化互不依赖，并发执行以压缩冷启动耗时至"较慢的那一个"。
  //
  // · 本地库必须早于 UI：Hive 需先注册 TypeAdapter 才能打开 Box，
  //   而观影记录的首屏读取发生在第一个 Provider 构建时（详情页 / 资料库页）。
  // · 播放内核（`MediaKit.ensureInitialized()`）必须早于任何 `Player` /
  //   `VideoController` 构造：它会加载各平台原生库（Windows 是
  //   `libmpv-2.dll` 全家桶）并注册平台通道，晚一步会直接抛
  //   "native library not found"。放在 `runApp` 之前最稳妥。
  await Future.wait(<Future<void>>[
    PlayerBootstrap.ensureInitialized(),
    WatchHistoryLocalDataSource.initialize(),
  ]);
  await _migrateLegacyWatchData();

  if (_isDesktop) {
    await _setupDesktopWindow();
  }

  // ProviderScope 是 Riverpod 的依赖注入根容器。
  // 所有 Provider 的装配集中在 presentation/providers/core_providers.dart。
  runApp(const ProviderScope(child: MovieHubApp()));
}

/// 一次性把第二阶段遗留在 SharedPreferences 中的观看进度 / 追剧收藏
/// 迁移进 Hive（幂等 + 永久标记，见 [WatchHistoryLocalDataSource.migrateLegacyIfNeeded]）。
///
/// 刻意吞掉异常：迁移失败不应阻止应用启动——
/// 最坏情况只是旧数据不再出现在资料库中，而新数据依旧可正常写入。
Future<void> _migrateLegacyWatchData() async {
  try {
    await WatchHistoryLocalDataSource().migrateLegacyIfNeeded();
  } catch (error, stack) {
    debugPrint('观看记录迁移失败（已忽略）：$error\n$stack');
  }
}

bool get _isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

/// Windows 桌面端窗口初始化。
///
/// 影视类应用需要足够宽度才能展开 4~6 列海报网格；同时设置最小尺寸，
/// 避免窗口被缩到无法使用网格布局的程度——最小宽 960 恰好落在
/// 「侧边栏形态 + 4 列」的断点（[AppLayout.medium]）上。
///
/// 性能提示：`BackdropFilter` 在部分集显 Windows 设备上开销较高。
/// 若目标机器出现明显掉帧，可将 `FrostedSurface.blurEnabled` 置为 false，
/// 全局降级为不透明面板（视觉层级依旧成立，仅失去磨砂质感）。
Future<void> _setupDesktopWindow() async {
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(1280, 820),
    minimumSize: Size(960, 640),
    center: true,
    title: AppConstants.appName,
    backgroundColor: Color(0xFFF5F6F8),
    titleBarStyle: TitleBarStyle.normal,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}
