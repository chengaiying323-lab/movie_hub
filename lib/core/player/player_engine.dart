import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'playback_source.dart';
import 'playback_state.dart';

/// 播放内核抽象。
///
/// 存在的意义
/// ------------------------------------------------------------------
/// 上层（播放页、控制层 UI、追剧逻辑）只依赖这个接口，**不依赖 media_kit**。
/// 这带来三个实际好处：
/// 1. **可替换**：iOS 若要用 AVPlayer 原生后端、桌面若要换成 fvp，
///    只需要新增一个 `implements PlayerEngine`，上层零改动；
/// 2. **可测试**：测试注入 `FakePlayerEngine` 就能验证
///    「播放到 95% 是否自动标记已看」「退出是否调了 endSession」，
///    不需要真的解码视频；
/// 3. **职责清晰**：内核只负责"把字节变成画面 + 上报状态"，
///    决不做进度回写、切集、换线路 —— 那些是页面层与 Provider 的事。
///
/// 状态上报约定
/// ------------------------------------------------------------------
/// [state] 是 `ValueListenable` 而非 `Stream`：
/// * 它天然带"当前值"（`state.value`），新挂载的 UI 不需要等下一次事件就能渲染；
/// * 播放位置更新频率可达 10Hz，UI 必须用 `ValueListenableBuilder`
///   把重建范围压在时间标签与进度条内部，**绝不允许**把它桥接进
///   Riverpod 全局 state（那会让整棵订阅树按帧重建）。
///
/// [PlaybackState.failure] 在"自动重试中"也是非空的：
/// 此时 `status == opening`，UI 应展示轻量的「正在重试」提示；
/// 只有当 `status == failed`（重试额度耗尽）才弹出可操作的错误面板。
abstract class PlayerEngine {
  /// 当前状态快照（可监听）。
  ValueListenable<PlaybackState> get state;

  /// 等价于 `state.value`，用于一次性读取。
  PlaybackState get current;

  /// 当前正在播放的源；未打开任何媒体时为 null。
  PlaybackSource? get currentSource;

  /// 是否已释放。释放后所有方法都应是安全的空操作。
  bool get isDisposed;

  /// 打开媒体。
  ///
  /// [autoPlay] 为 false 时只做预加载（用于"用户点了卡片但还没点播放"的场景，
  /// 或需要先弹续播浮层再决定是否播放）。
  ///
  /// 实现约定：**不把 `source.startPositionMs` 交给内核的 open 参数**，
  /// 而是在拿到时长后执行一次 Seek —— 多数内核在 open 完成前 Seek 会被丢弃。
  Future<void> open(PlaybackSource source, {bool autoPlay = true});

  /// 继续播放。若已播放到末尾，则从头开始。
  Future<void> play();

  Future<void> pause();

  /// 播放/暂停切换（控制层的空格键、点击画面都走这里）。
  Future<void> togglePlay();

  /// 定位到指定位置（越界值由实现 clamp 到 `[0, duration]`）。
  Future<void> seek(Duration position);

  /// 相对定位（双击快进/快退、方向键）。
  Future<void> seekBy(Duration offset);

  /// 设置倍速。范围由实现收敛到 `0.25 ~ 4.0`。
  Future<void> setRate(double rate);

  /// 设置音量（0 ~ 100，与 mpv 属性域一致）。
  Future<void> setVolume(double volume);

  /// 手动重试：重置重试计数与硬解降级标记，立即重新打开当前源。
  Future<void> retry();

  /// 停止播放并回到 idle（切换线路/选集时由页面层调用）。
  Future<void> stop();

  /// 视频渲染面（`Widget` 抽象工厂）。
  ///
  /// 由实现返回自己内核的渲染组件，上层只负责把它塞进布局。
  /// 之所以返回 `Widget` 而不是暴露 `VideoController`：
  /// 后者会把 media_kit 的类型泄漏到所有调用点，换内核就得改一圈。
  Widget buildVideo({BoxFit fit = BoxFit.contain});

  /// 释放内核资源。必须可重复调用。
  Future<void> dispose();
}
