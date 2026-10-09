import 'dart:ui' show FontFeature;

// ValueListenable / ValueNotifier 定义在 foundation 里，
// 而 packages/flutter/lib/widgets.dart 只从 foundation 导出了 UniqueKey
// （`export 'foundation.dart' show UniqueKey;`），因此 material.dart
// **不会**把 ValueListenable 带进来，必须显式导入。
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/player/playback_state.dart';
import '../../theme/player_palette.dart';

/// 可拖拽的播放进度条。
///
/// 三段式轨道
/// ------------------------------------------------------------------
/// ```
/// ▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░░░    ← 已缓冲（浅白 45%）
/// ██████░░░░░░░░░░░░░░░░░░░░░░░░    ← 已播放（accent 珊瑚红）
/// ```
/// 缓冲段必须画出来：弱网时用户需要知道"是卡了还是在加载" ——
/// 缓冲条在推进说明数据在来，只是慢；缓冲条停住才是真断流。
///
/// 拖动期间**冻结外部状态**
/// ------------------------------------------------------------------
/// 拖动时若继续用播放器上报的 `position` 绘制，手指和滑块会互相打架
/// （播放器每 100ms 回一次位置，把滑块拽回去）。因此拖动开始时把当前值
/// 快照进 [_dragFraction] 并屏蔽外部更新，松手才调用 [onSeek]。
class PlayerProgressBar extends StatefulWidget {
  const PlayerProgressBar({
    super.key,
    required this.state,
    required this.onSeek,
    this.enabled = true,
    this.showDragBubble = true,
  });

  /// 播放状态（高频更新，只在本组件内部监听）。
  final ValueListenable<PlaybackState> state;

  /// 松手后回调目标位置。
  final ValueChanged<Duration> onSeek;

  /// 直播或时长未知时为 false，此时只展示不响应手势。
  final bool enabled;

  /// 拖动时是否显示时间气泡。
  final bool showDragBubble;

  /// 轨道视觉厚度。
  static const double trackHeight = 3.5;

  /// 拖拽手柄直径。
  static const double thumbSize = 12;

  /// 手势命中区高度（触控友好的关键：视觉 3.5px，命中 32px）。
  static const double hitHeight = 32;

  @override
  State<PlayerProgressBar> createState() => _PlayerProgressBarState();
}

class _PlayerProgressBarState extends State<PlayerProgressBar> {
  bool _dragging = false;
  double _dragFraction = 0;
  Duration _dragPosition = Duration.zero;

  /// 把手指的横向位置换算为 `0.0 ~ 1.0`。
  double _fractionOf(double dx, double width) {
    if (width <= 0) return 0;
    return _clamp01(dx / width);
  }

  void _beginDrag(double dx, double width, Duration duration) {
    setState(() {
      _dragging = true;
      _dragFraction = _fractionOf(dx, width);
      _dragPosition = duration * _dragFraction;
    });
  }

  void _updateDrag(double dx, double width, Duration duration) {
    final fraction = _fractionOf(dx, width);
    setState(() {
      _dragFraction = fraction;
      _dragPosition = duration * fraction;
    });
  }

  void _endDrag({required bool commit}) {
    if (!_dragging) return;
    final target = _dragPosition;
    setState(() => _dragging = false);
    if (commit) widget.onSeek(target);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return ValueListenableBuilder<PlaybackState>(
          valueListenable: widget.state,
          builder: (context, snapshot, _) {
            final duration = snapshot.duration;
            final interactive =
                widget.enabled && duration > Duration.zero && width > 0;

            final played = _dragging ? _dragFraction : snapshot.progress;
            final buffered = _dragging ? _dragFraction : snapshot.bufferedProgress;

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              // 点击直达（桌面端鼠标单击是最常用的定位方式）
              onTapDown: interactive
                  ? (details) {
                      final fraction = _fractionOf(details.localPosition.dx, width);
                      widget.onSeek(duration * fraction);
                    }
                  : null,
              onHorizontalDragStart: interactive
                  ? (details) => _beginDrag(
                        details.localPosition.dx,
                        width,
                        duration,
                      )
                  : null,
              onHorizontalDragUpdate: interactive
                  ? (details) => _updateDrag(
                        details.localPosition.dx,
                        width,
                        duration,
                      )
                  : null,
              onHorizontalDragEnd: interactive
                  ? (_) => _endDrag(commit: true)
                  : null,
              onHorizontalDragCancel:
                  interactive ? () => _endDrag(commit: false) : null,
              child: SizedBox(
                height: PlayerProgressBar.hitHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: <Widget>[
                    _Track(
                      played: played,
                      buffered: buffered,
                      highlighted: _dragging,
                    ),
                    if (interactive)
                      Positioned(
                        left: (played * width) -
                            PlayerProgressBar.thumbSize / 2,
                        child: _Thumb(active: _dragging),
                      ),
                    if (_dragging && widget.showDragBubble)
                      Positioned(
                        left: _bubbleLeft(played, width),
                        top: -32,
                        child: _DragBubble(position: _dragPosition),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// 时间气泡的左偏移：跟随滑块但要贴边收住，避免溢出画面。
double _bubbleLeft(double fraction, double width) {
  const bubbleWidth = 104.0;
  final raw = fraction * width - bubbleWidth / 2;
  final maxLeft = width - bubbleWidth;
  if (maxLeft <= 0) return 0;
  if (raw < 0) return 0;
  if (raw > maxLeft) return maxLeft;
  return raw;
}

/// `0.0 ~ 1.0` 收敛。
///
/// 刻意用显式比较而非 `num.clamp`：`clamp` 的静态返回类型是 `num`，
/// 在需要 `double` 的位置上会引入一次不必要的显式转换，
/// 而这里的语义又非常单一，直接写清楚更省心。
double _clamp01(double value) {
  if (value < 0) return 0;
  if (value > 1) return 1;
  return value;
}

class _Track extends StatelessWidget {
  const _Track({
    required this.played,
    required this.buffered,
    required this.highlighted,
  });

  final double played;
  final double buffered;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(PlayerProgressBar.trackHeight / 2),
      child: SizedBox(
        height: highlighted
            ? PlayerProgressBar.trackHeight + 1.5
            : PlayerProgressBar.trackHeight,
        child: Stack(
          children: <Widget>[
            const Positioned.fill(
              child: ColoredBox(color: PlayerPalette.track),
            ),
            Positioned.fill(
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: _clamp01(buffered),
                child: const ColoredBox(color: PlayerPalette.buffered),
              ),
            ),
            Positioned.fill(
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: _clamp01(played),
                child: const ColoredBox(color: PlayerPalette.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final size = active
        ? PlayerProgressBar.thumbSize + 4
        : PlayerProgressBar.thumbSize;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: PlayerPalette.thumb,
        shape: BoxShape.circle,
        boxShadow: <BoxShadow>[
          BoxShadow(color: Color(0x66000000), blurRadius: 6, offset: Offset(0, 1)),
        ],
      ),
    );
  }
}

/// 拖动时的时间气泡。
class _DragBubble extends StatelessWidget {
  const _DragBubble({required this.position});

  final Duration position;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 104,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: PlayerPalette.panelElevated,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: PlayerPalette.hairlineStrong,
          width: 0.8,
        ),
      ),
      child: Text(
        PlaybackState.formatDuration(position),
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: PlayerPalette.ink,
          fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
