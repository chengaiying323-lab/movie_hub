import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/design/design.dart';
import '../../../core/player/player.dart';
import '../../theme/player_palette.dart';
import 'player_error_panel.dart';

/// 视频渲染 + 手势 + 状态反馈的**高内聚**封装。
///
/// 职责边界
/// ------------------------------------------------------------------
/// 本组件只管"把引擎的画面呈现出来，并把用户的手势翻译成引擎调用"：
/// * 渲染：转发 [PlayerEngine.buildVideo]（不同内核的渲染面不同）；
/// * 手势：单击显隐控制层、双击左右快退/快进 10 秒、鼠标移动唤醒控制层；
/// * 反馈：缓冲转圈、自动重试提示、弱网悬浮换源、失败浮层。
///
/// 它**不关心**：进度回写、切集、换线路、全屏 —— 那些是播放页的职责
/// （需要通过 [overlay] 注进来）。这样同一个组件可以原样用在
/// 小窗预览、投屏预览等场景。
///
/// 手势冲突的处理
/// ------------------------------------------------------------------
/// Flutter 原生的 `onTap` + `onDoubleTap` 组合会让单击**必须等 300ms**
/// 才能确认（等不到第二次点击才敢触发），表现在界面上就是"点了没反应"。
/// 因此这里自己实现判定：单击立刻生效，若 220ms 内出现第二次点击，
/// 则撤销第一次的显隐动作、改判为双击 seek。
class VideoPlayerComponent extends StatefulWidget {
  const VideoPlayerComponent({
    super.key,
    required this.engine,
    this.overlay,
    this.controlsVisible = true,
    this.onToggleControls,
    this.onUserActivity,
    this.onErrorRetry,
    this.onErrorSwitchSource,
    this.onErrorExit,
    this.onDoubleTapSeek,
    this.fit = BoxFit.contain,
    this.enableGestures = true,
  });

  final PlayerEngine engine;

  /// 控制层（由播放页注入 [ControlsOverlay]）。
  final Widget? overlay;

  /// 控制层是否可见。隐藏时会淡出并忽略指针事件。
  final bool controlsVisible;

  /// 单击画面：请求切换控制层显隐。
  final VoidCallback? onToggleControls;

  /// 任何用户活动（移动鼠标 / 点击 / 滚轮）。
  /// 播放页据此重新计时自动隐藏。
  final VoidCallback? onUserActivity;

  final VoidCallback? onErrorRetry;
  final VoidCallback? onErrorSwitchSource;
  final VoidCallback? onErrorExit;

  /// 双击左右快进/快退（参数为相对位移，负数为快退）。
  final ValueChanged<Duration>? onDoubleTapSeek;

  final BoxFit fit;
  final bool enableGestures;

  @override
  State<VideoPlayerComponent> createState() => _VideoPlayerComponentState();
}

class _VideoPlayerComponentState extends State<VideoPlayerComponent> {
  /// 单击等待双击的窗口。取 220ms 而非 Flutter 默认的 300ms：
  /// 300ms 在"想显示控制层"的场景下已经能被感知为迟钝。
  static const Duration _doubleTapWindow = Duration(milliseconds: 220);

  /// 弱网悬浮提示的出现延时。
  ///
  /// 不能一缓冲就弹提示：正常起播、正常切分片都会有短暂缓冲，
  /// 那属于"正常现象"。8 秒是个经验阈值 —— 超过它用户一定已经开始烦躁了。
  static const Duration _weakNetworkDelay = Duration(seconds: 8);

  /// 双击提示的展示时长。
  static const Duration _seekHudDuration = Duration(milliseconds: 700);

  Timer? _tapTimer;
  Timer? _weakNetworkTimer;
  Timer? _hudTimer;

  DateTime? _lastTapAt;
  Offset? _lastTapPosition;

  bool _weakNetwork = false;
  String? _seekHud;

  @override
  void initState() {
    super.initState();
    widget.engine.state.addListener(_onStateChanged);
    _onStateChanged();
  }

  @override
  void didUpdateWidget(covariant VideoPlayerComponent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.engine != widget.engine) {
      oldWidget.engine.state.removeListener(_onStateChanged);
      widget.engine.state.addListener(_onStateChanged);
    }
  }

  @override
  void dispose() {
    widget.engine.state.removeListener(_onStateChanged);
    _tapTimer?.cancel();
    _weakNetworkTimer?.cancel();
    _hudTimer?.cancel();
    super.dispose();
  }

  /// 弱网计时：只在"缓冲中且用户想播"时启动。
  void _onStateChanged() {
    final status = widget.engine.current.status;
    final shouldWatch = status == PlaybackStatus.buffering ||
        status == PlaybackStatus.opening;

    if (!shouldWatch) {
      _weakNetworkTimer?.cancel();
      _weakNetworkTimer = null;
      if (_weakNetwork && mounted) setState(() => _weakNetwork = false);
      return;
    }

    if (_weakNetworkTimer == null) {
      _weakNetworkTimer = Timer(_weakNetworkDelay, () {
        if (mounted) setState(() => _weakNetwork = true);
      });
    }
  }

  // ── 手势 ────────────────────────────────────────────────

  void _handleTap(Offset local, double width) {
    widget.onUserActivity?.call();

    final now = DateTime.now();
    final previous = _lastTapAt;
    final previousPosition = _lastTapPosition;

    final isDoubleTap = previous != null &&
        now.difference(previous) < _doubleTapWindow &&
        previousPosition != null &&
        (previousPosition.dx - local.dx).abs() < 80 &&
        (previousPosition.dy - local.dy).abs() < 80;

    if (isDoubleTap) {
      _tapTimer?.cancel();
      _tapTimer = null;
      _lastTapAt = null;
      _lastTapPosition = null;
      _handleDoubleTap(local, width);
      return;
    }

    _lastTapAt = now;
    _lastTapPosition = local;
    _tapTimer?.cancel();
    _tapTimer = Timer(_doubleTapWindow, () {
      _tapTimer = null;
      _lastTapAt = null;
      _lastTapPosition = null;
      widget.onToggleControls?.call();
    });
  }

  void _handleDoubleTap(Offset local, double width) {
    if (width <= 0) return;

    // 左 40% 快退、右 40% 快进、中间 20% 只当作"显示控制层"的误触。
    // 留出中间缓冲带是因为双击画面正中在多数播放器里没有明确语义，
    // 误判成快进 10 秒比"没反应"更让人困惑。
    final fraction = local.dx / width;
    final Duration offset;

    if (fraction <= 0.4) {
      offset = -PlayerEngineConfig.doubleTapSeekStep;
    } else if (fraction >= 0.6) {
      offset = PlayerEngineConfig.doubleTapSeekStep;
    } else {
      widget.onToggleControls?.call();
      return;
    }

    widget.onDoubleTapSeek?.call(offset);
    unawaited(widget.engine.seekBy(offset));
    _showSeekHud(offset);
  }

  void _showSeekHud(Duration offset) {
    final seconds = offset.inSeconds.abs();
    setState(() {
      _seekHud = offset.isNegative ? '快退 $seconds 秒' : '快进 $seconds 秒';
    });
    _hudTimer?.cancel();
    _hudTimer = Timer(_seekHudDuration, () {
      if (mounted) setState(() => _seekHud = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        return ColoredBox(
          color: PlayerPalette.videoBackground,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // ① 画面
              Center(child: widget.engine.buildVideo(fit: widget.fit)),

              // ② 手势层（必须铺满，否则空白区域点不到）
              if (widget.enableGestures)
                Positioned.fill(
                  child: MouseRegion(
                    onHover: (_) => widget.onUserActivity?.call(),
                    child: Listener(
                      onPointerSignal: (_) => widget.onUserActivity?.call(),
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTapUp: (details) =>
                            _handleTap(details.localPosition, width),
                        onLongPressStart: (_) => widget.onUserActivity?.call(),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),

              // ③ 双击 seek 提示
              if (_seekHud != null)
                IgnorePointer(child: Center(child: _SeekHud(label: _seekHud!))),

              // ④ 缓冲 / 自动重试提示
              _StatusIndicator(engine: widget.engine),

              // ⑤ 弱网悬浮动作（一键换源 / 重试）
              if (_weakNetwork && widget.overlay != null)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 96),
                    child: _WeakNetworkBar(
                      onRetry: widget.onErrorRetry,
                      onSwitchSource: widget.onErrorSwitchSource,
                    ),
                  ),
                ),

              // ⑥ 控制层
              if (widget.overlay != null)
                IgnorePointer(
                  ignoring: !widget.controlsVisible,
                  child: AnimatedOpacity(
                    opacity: widget.controlsVisible ? 1 : 0,
                    duration: AppMotion.fast,
                    curve: AppMotion.standard,
                    child: widget.overlay!,
                  ),
                ),

              // ⑦ 失败浮层（放在最上层，且不受控制层显隐影响）
              _FailureLayer(
                engine: widget.engine,
                onRetry: widget.onErrorRetry,
                onSwitchSource: widget.onErrorSwitchSource,
                onExit: widget.onErrorExit,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 双击 seek 的中央提示。
class _SeekHud extends StatelessWidget {
  const _SeekHud({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: PlayerPalette.controlBgHover,
        borderRadius: AppRadius.pillBR,
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: PlayerPalette.ink,
        ),
      ),
    );
  }
}

/// 缓冲 / 打开中 / 自动重试 的统一指示器。
///
/// 关键区分：**自动重试期间 `failure` 非空但 `status != failed`**，
/// 此时显示的是"正在重试"而不是错误面板 —— 用户不需要做任何事，
/// 给一个可操作的错误面板反而会让他以为必须手动干预。
class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator({required this.engine});

  final PlayerEngine engine;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlaybackState>(
      valueListenable: engine.state,
      builder: (context, state, _) {
        final retrying = state.status == PlaybackStatus.opening &&
            state.failure != null &&
            state.failure!.attempt > 0;

        final visible = retrying ||
            state.status == PlaybackStatus.buffering ||
            (state.status == PlaybackStatus.opening && state.failure == null);

        if (!visible) return const SizedBox.shrink();

        return IgnorePointer(
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: PlayerPalette.controlBg,
                borderRadius: AppRadius.smBR,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        PlayerPalette.accent,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    retrying
                        ? '连接不稳定，正在自动重试（第 ${state.failure!.attempt} 次）'
                        : state.status.label,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: PlayerPalette.inkSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 弱网悬浮动作条。
class _WeakNetworkBar extends StatelessWidget {
  const _WeakNetworkBar({this.onRetry, this.onSwitchSource});

  final VoidCallback? onRetry;
  final VoidCallback? onSwitchSource;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: PlayerPalette.frosted,
        borderRadius: AppRadius.pillBR,
        border: Border.all(
          color: PlayerPalette.hairlineStrong,
          width: AppStroke.hairline,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: Text(
              '画面卡住了？',
              style: TextStyle(
                fontSize: 12.5,
                color: PlayerPalette.inkSecondary,
              ),
            ),
          ),
          if (onRetry != null)
            _PillAction(
              label: '重试',
              icon: Icons.refresh_rounded,
              onTap: onRetry!,
            ),
          if (onSwitchSource != null) ...<Widget>[
            const SizedBox(width: 4),
            _PillAction(
              label: '换线路',
              icon: Icons.swap_horiz_rounded,
              highlighted: true,
              onTap: onSwitchSource!,
            ),
          ],
        ],
      ),
    );
  }
}

class _PillAction extends StatelessWidget {
  const _PillAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.highlighted = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: highlighted ? PlayerPalette.accent : PlayerPalette.controlBg,
            borderRadius: AppRadius.pillBR,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                icon,
                size: 14,
                color: highlighted ? Colors.white : PlayerPalette.inkSecondary,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color:
                      highlighted ? Colors.white : PlayerPalette.inkSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 失败浮层：只有 `status == failed` 时才出现。
class _FailureLayer extends StatelessWidget {
  const _FailureLayer({
    required this.engine,
    this.onRetry,
    this.onSwitchSource,
    this.onExit,
  });

  final PlayerEngine engine;
  final VoidCallback? onRetry;
  final VoidCallback? onSwitchSource;
  final VoidCallback? onExit;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlaybackState>(
      valueListenable: engine.state,
      builder: (context, state, _) {
        final failure = state.failure;
        if (state.status != PlaybackStatus.failed || failure == null) {
          return const SizedBox.shrink();
        }
        return GestureDetector(
          // 必须显式吞掉点击：`ColoredBox` 只负责画，不参与命中测试，
          // 不加这一层的话点击会穿透到底下的控制层，
          // 用户按在"重试"旁边就可能误触到播放/暂停。
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          child: ColoredBox(
            color: const Color(0xB3000000),
            child: PlayerErrorPanel(
              failure: failure,
              onRetry: onRetry ?? () => unawaited(engine.retry()),
              onSwitchSource: onSwitchSource,
              onExit: onExit,
            ),
          ),
        );
      },
    );
  }
}
