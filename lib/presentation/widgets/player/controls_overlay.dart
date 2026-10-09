import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../../../core/design/design.dart';
import '../../../core/player/player.dart';
import '../../theme/player_palette.dart';
import 'player_progress_bar.dart';
import 'player_speed_menu.dart';

/// 播放控制层（Controls Overlay）。
///
/// 视觉约定
/// ------------------------------------------------------------------
/// 整层置于**半透明暗色渐变**之上：顶部 70% 黑 → 透明、底部 80% 黑 → 透明。
/// 目的不是"好看"，而是保证白墙、雪景这类高光画面下按钮与文字依然可读，
/// 同时保留中间画面完全通透（遮罩不能盖住画面主体）。
///
/// 布局分三带
/// ```text
/// ┌──────────────────────────────────────────┐
/// │ ← 标题 / 线路·集名                 🔒 锁  │  顶栏
/// │                                          │
/// │                ▶ / ⏸                     │  中区（大按钮）
/// │                                          │
/// │ 01:23 ─────────●──────────── 01:45:00    │  进度
/// │ 1.0x   选集   线路                   ⛶   │  动作
/// └──────────────────────────────────────────┘
/// ```
///
/// 重建范围
/// ------------------------------------------------------------------
/// 只把两处包在 `ValueListenableBuilder` 里（中区大按钮、时间与进度），
/// 顶栏与动作栏完全不依赖播放状态 —— 位置回调 10Hz，能少重建一点是一点。
class ControlsOverlay extends StatelessWidget {
  const ControlsOverlay({
    super.key,
    required this.engine,
    required this.title,
    this.subtitle,
    required this.onClose,
    this.onOpenEpisodes,
    this.onOpenSources,
    this.onToggleFullscreen,
    this.isFullscreen = false,
    this.onToggleLock,
    this.locked = false,
    this.topInset = 0,
    this.bottomInset = 0,
  });

  final PlayerEngine engine;

  /// 主标题（影片名）。
  final String title;

  /// 副标题（线路 · 集名）。
  final String? subtitle;

  /// 返回 / 收起。
  final VoidCallback onClose;

  /// 打开选集抽屉。为 null 时隐藏入口（单集影片）。
  final VoidCallback? onOpenEpisodes;

  /// 打开线路抽屉。为 null（只有一条线路）时隐藏入口。
  final VoidCallback? onOpenSources;

  /// 全屏 / 退出全屏。为 null 时隐藏入口。
  final VoidCallback? onToggleFullscreen;

  final bool isFullscreen;

  /// 锁屏开关（移动端防误触）。
  final VoidCallback? onToggleLock;

  final bool locked;

  /// 由页面传入的安全区补偿（全屏时系统栏会被隐藏，仍需避开刘海）。
  final double topInset;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    if (locked) {
      return _LockedLayer(
        topInset: topInset,
        onUnlock: onToggleLock,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // 顶部渐变遮罩（不拦截指针事件）
        IgnorePointer(
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              height: 108,
              decoration: const BoxDecoration(
                gradient: PlayerPalette.topScrim,
              ),
            ),
          ),
        ),
        // 底部渐变遮罩
        IgnorePointer(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: 168,
              decoration: const BoxDecoration(
                gradient: PlayerPalette.bottomScrim,
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(top: topInset, bottom: bottomInset),
          child: Column(
            children: <Widget>[
              _TopBar(
                engine: engine,
                title: title,
                subtitle: subtitle,
                onClose: onClose,
                onToggleLock: onToggleLock,
              ),
              Expanded(child: _CenterControls(engine: engine)),
              _BottomBar(
                engine: engine,
                onOpenEpisodes: onOpenEpisodes,
                onOpenSources: onOpenSources,
                onToggleFullscreen: onToggleFullscreen,
                isFullscreen: isFullscreen,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── 顶栏 ──────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.engine,
    required this.title,
    required this.onClose,
    this.subtitle,
    this.onToggleLock,
  });

  final PlayerEngine engine;
  final String title;
  final String? subtitle;
  final VoidCallback onClose;
  final VoidCallback? onToggleLock;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          _IconButton(
            icon: Icons.arrow_back_rounded,
            tooltip: '返回',
            onTap: onClose,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: PlayerPalette.ink,
                  ),
                ),
                if (subtitle != null && subtitle!.trim().isNotEmpty)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: PlayerPalette.inkTertiary,
                    ),
                  ),
              ],
            ),
          ),
          // 分辨率徽标：用户判断"这条线路画质如何"时，最直接的事实就是它。
          _ResolutionBadge(engine: engine),
          if (onToggleLock != null)
            _IconButton(
              icon: Icons.lock_open_rounded,
              tooltip: '锁定控制层',
              onTap: onToggleLock!,
            ),
        ],
      ),
    );
  }
}

/// 当前解码分辨率徽标（未知时不占位）。
class _ResolutionBadge extends StatelessWidget {
  const _ResolutionBadge({required this.engine});

  final PlayerEngine engine;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlaybackState>(
      valueListenable: engine.state,
      builder: (context, state, _) {
        if (state.videoWidth <= 0 || state.videoHeight <= 0) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(right: AppSpacing.xs),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: PlayerPalette.chipBg,
              borderRadius: AppRadius.xsBR,
            ),
            child: Text(
              '${state.videoWidth}×${state.videoHeight}',
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: PlayerPalette.inkSecondary,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── 中区大按钮 ────────────────────────────────────────────

class _CenterControls extends StatelessWidget {
  const _CenterControls({required this.engine});

  final PlayerEngine engine;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlaybackState>(
      valueListenable: engine.state,
      builder: (context, state, _) {
        // 加载圈由 `VideoPlayerComponent` 统一绘制（它必须与控制层显隐无关，
        // 否则控制层自动隐藏后用户就只能盯着黑屏）。这里给一个等尺寸的
        // 透明占位，既避免画出第二个圈重叠在一起，又保持布局不跳动。
        final loading = state.status == PlaybackStatus.buffering ||
            state.status == PlaybackStatus.opening;

        return Row(
          children: <Widget>[
            // 左侧 10 秒快退热区（与双击手势不冲突：这里用的是明确的按钮语义，
            // 桌面端鼠标单击也能用）
            Expanded(
              child: _SideSeekButton(
                icon: Icons.replay_10_rounded,
                tooltip: '快退 10 秒',
                onTap: () =>
                    engine.seekBy(-PlayerEngineConfig.doubleTapSeekStep),
              ),
            ),
            if (loading)
              const SizedBox(width: 64, height: 64)
            else
              _BigPlayButton(playing: state.isPlaying, onTap: engine.togglePlay),
            Expanded(
              child: _SideSeekButton(
                icon: Icons.forward_10_rounded,
                tooltip: '快进 10 秒',
                onTap: () => engine.seekBy(PlayerEngineConfig.doubleTapSeekStep),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SideSeekButton extends StatelessWidget {
  const _SideSeekButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Tooltip(
        message: tooltip,
        child: IconButton(
          onPressed: onTap,
          iconSize: 30,
          color: PlayerPalette.inkSecondary,
          splashRadius: 26,
          icon: Icon(icon),
        ),
      ),
    );
  }
}

class _BigPlayButton extends StatelessWidget {
  const _BigPlayButton({required this.playing, required this.onTap});

  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: PlayerPalette.controlBg,
            shape: BoxShape.circle,
          ),
          child: Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 36,
            color: PlayerPalette.ink,
          ),
        ),
      ),
    );
  }
}

// ── 底栏 ──────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.engine,
    this.onOpenEpisodes,
    this.onOpenSources,
    this.onToggleFullscreen,
    this.isFullscreen = false,
  });

  final PlayerEngine engine;
  final VoidCallback? onOpenEpisodes;
  final VoidCallback? onOpenSources;
  final VoidCallback? onToggleFullscreen;
  final bool isFullscreen;

  @override
  Widget build(BuildContext context) {
    final live = engine.currentSource?.isLive ?? false;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        0,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _TimeAndProgress(engine: engine, live: live),
          const SizedBox(height: AppSpacing.xxs),
          Row(
            children: <Widget>[
              _SpeedAction(engine: engine),
              // 桌面端才有静音按钮：移动端的音量由硬件按键控制，
              // 在横屏窄高度里再塞一个按钮只会挤压选集/线路这两个高频入口。
              if (AppLayout.of(context).isDesktop) ...<Widget>[
                const SizedBox(width: AppSpacing.xs),
                _VolumeAction(engine: engine),
              ],
              if (onOpenEpisodes != null) ...<Widget>[
                const SizedBox(width: AppSpacing.xs),
                _IconAction(
                  icon: Icons.list_rounded,
                  label: '选集',
                  onTap: onOpenEpisodes!,
                ),
              ],
              if (onOpenSources != null) ...<Widget>[
                const SizedBox(width: AppSpacing.xs),
                _IconAction(
                  icon: Icons.swap_horiz_rounded,
                  label: '线路',
                  onTap: onOpenSources!,
                ),
              ],
              const Spacer(),
              if (onToggleFullscreen != null)
                _IconAction(
                  icon: isFullscreen
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                  label: isFullscreen ? '退出全屏' : '全屏',
                  onTap: onToggleFullscreen!,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimeAndProgress extends StatelessWidget {
  const _TimeAndProgress({required this.engine, required this.live});

  final PlayerEngine engine;
  final bool live;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlaybackState>(
      valueListenable: engine.state,
      builder: (context, state, _) {
        final seekable = !live && state.isSeekable;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            _TimeLabel(text: PlaybackState.formatDuration(state.position)),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: live
                  ? const _LiveTrack()
                  : PlayerProgressBar(
                      state: engine.state,
                      enabled: seekable,
                      onSeek: engine.seek,
                    ),
            ),
            const SizedBox(width: AppSpacing.xs),
            _TimeLabel(
              text: live
                  ? '直播'
                  : (state.isSeekable
                      ? PlaybackState.formatDuration(state.duration)
                      : '--:--'),
              muted: !seekable,
            ),
          ],
        );
      },
    );
  }
}

/// 直播的"进度条"：只表达"正在直播"，不可拖动。
class _LiveTrack extends StatelessWidget {
  const _LiveTrack();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: PlayerProgressBar.hitHeight,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          width: 56,
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: PlayerPalette.dangerSoft,
            borderRadius: AppRadius.pillBR,
          ),
          child: const Text(
            'LIVE',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: PlayerPalette.danger,
            ),
          ),
        ),
      ),
    );
  }
}

class _TimeLabel extends StatelessWidget {
  const _TimeLabel({required this.text, this.muted = false});

  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
        // 等宽数字：否则秒数从 09 跳到 10 时整行宽度会抖
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        color: muted ? PlayerPalette.inkFaint : PlayerPalette.inkSecondary,
      ),
    );
  }
}

// ── 底栏动作 ──────────────────────────────────────────────

class _SpeedAction extends StatefulWidget {
  const _SpeedAction({required this.engine});

  final PlayerEngine engine;

  @override
  State<_SpeedAction> createState() => _SpeedActionState();
}

class _SpeedActionState extends State<_SpeedAction> {
  final GlobalKey _anchorKey = GlobalKey();

  Future<void> _open() async {
    final selected = await PlayerSpeedMenu.show(
      context,
      anchorKey: _anchorKey,
      current: widget.engine.current.rate,
    );
    if (selected == null) return;
    await widget.engine.setRate(selected);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlaybackState>(
      valueListenable: widget.engine.state,
      builder: (context, state, _) {
        // 1.0 是默认值，显示成"倍速"而不是"1.0x"，
        // 让"我改过倍速"这件事在界面上一眼可见。
        final isDefault = (state.rate - 1.0).abs() < 0.001;
        return KeyedSubtree(
          key: _anchorKey,
          child: _IconAction(
            icon: Icons.speed_rounded,
            label: isDefault ? '倍速' : '${state.rate}x',
            highlighted: !isDefault,
            onTap: _open,
          ),
        );
      },
    );
  }
}

/// 静音切换。
///
/// 只做静音/恢复，不做音量滑杆：滑杆需要一条额外的弹出轨道，
/// 而桌面端用户更习惯直接拧系统音量或键盘功能键——
/// 播放器里最需要的只是"一键闭嘴"（接电话、开会时）。
class _VolumeAction extends StatefulWidget {
  const _VolumeAction({required this.engine});

  final PlayerEngine engine;

  @override
  State<_VolumeAction> createState() => _VolumeActionState();
}

class _VolumeActionState extends State<_VolumeAction> {
  /// 静音前记住的音量，用于恢复。
  double _previousVolume = 100;

  Future<void> _toggle() async {
    final current = widget.engine.current.volume;
    if (current > 0) {
      _previousVolume = current;
      await widget.engine.setVolume(0);
      return;
    }
    await widget.engine.setVolume(_previousVolume <= 0 ? 100 : _previousVolume);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlaybackState>(
      valueListenable: widget.engine.state,
      builder: (context, state, _) {
        final muted = state.volume <= 0;
        return _IconAction(
          icon: muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
          label: '音量',
          highlighted: muted,
          onTap: () => unawaited(_toggle()),
        );
      },
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final color =
        highlighted ? PlayerPalette.accent : PlayerPalette.inkSecondary;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: PlayerPalette.controlBg,
            borderRadius: AppRadius.xsBR,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onTap,
        iconSize: 22,
        color: PlayerPalette.ink,
        splashRadius: 22,
        icon: Icon(icon),
      ),
    );
  }
}

// ── 锁定态 ────────────────────────────────────────────────

/// 锁屏后只保留一个解锁按钮。
///
/// 为什么需要：移动端全屏播放时，握持手机的虎口极易误触进度条 ——
/// 一次误触就把电影拖到结尾。锁定后除解锁外一切手势失效。
class _LockedLayer extends StatelessWidget {
  const _LockedLayer({required this.topInset, this.onUnlock});

  final double topInset;
  final VoidCallback? onUnlock;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // 拦截所有点击，避免穿透到下方的单击显隐手势
        const ModalBarrier(
          color: Colors.transparent,
          dismissible: false,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: EdgeInsets.only(
              left: AppSpacing.md,
              top: topInset,
            ),
            child: GestureDetector(
              onTap: onUnlock,
              behavior: HitTestBehavior.opaque,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: PlayerPalette.controlBg,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock_rounded,
                    size: 18,
                    color: PlayerPalette.ink,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
