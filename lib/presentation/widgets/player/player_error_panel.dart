import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/design/design.dart';
import '../../../core/player/playback_state.dart';
import '../../theme/player_palette.dart';

/// 播放失败浮层。
///
/// 设计原则：**动作由失败类型决定，而不是"什么都给一个"**
/// ------------------------------------------------------------------
/// 用户面对播放失败时能做且愿意做的只有三件事：重试、换线路、放弃。
/// 把三个按钮全部平铺出来会让用户逐个试，反而浪费时间。
/// 因此本组件读 [PlaybackFailure.canRetry] / [PlaybackFailure.canSwitchSource]：
/// * 403/404/需解析 → 「换线路」是主按钮（重试几乎必然同样失败）；
/// * 超时/断流/网络 → 「重试」是主按钮；
/// * 两者都可 → 主按钮跟随 `switchSource`，另一个降为次级按钮。
///
/// 原始报错默认折叠：普通用户看不懂，但反馈问题时又必须能拿到，
/// 所以给一个「复制错误信息」而不是把它铺在主界面上。
class PlayerErrorPanel extends StatefulWidget {
  const PlayerErrorPanel({
    super.key,
    required this.failure,
    required this.onRetry,
    this.onSwitchSource,
    this.onExit,
    this.title,
  });

  final PlaybackFailure failure;

  /// 手动重试（重置重试计数后重开当前源）。
  final VoidCallback onRetry;

  /// 打开线路抽屉。为 null 时隐藏「换线路」按钮。
  final VoidCallback? onSwitchSource;

  /// 退出播放页。
  final VoidCallback? onExit;

  /// 覆盖标题（如"该线路不可用"）。
  final String? title;

  @override
  State<PlayerErrorPanel> createState() => _PlayerErrorPanelState();
}

class _PlayerErrorPanelState extends State<PlayerErrorPanel> {
  bool _showDetail = false;
  bool _copied = false;

  Future<void> _copyDetail() async {
    final raw = widget.failure.rawError ?? widget.failure.message;
    await Clipboard.setData(ClipboardData(text: raw));
    if (!mounted) return;
    setState(() => _copied = true);
    // 只是给个"复制成功"的短反馈，不做 Toast 依赖
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final failure = widget.failure;
    final primaryIsSwitch = failure.canSwitchSource && widget.onSwitchSource != null;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          margin: const EdgeInsets.all(AppSpacing.lg),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: PlayerPalette.frosted,
            borderRadius: AppRadius.panelBR,
            border: Border.all(
              color: PlayerPalette.hairlineStrong,
              width: AppStroke.hairline,
            ),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x99000000),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    _iconFor(failure.kind),
                    size: 20,
                    color: PlayerPalette.warning,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      widget.title ?? failure.title,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: PlayerPalette.ink,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                failure.hint,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: PlayerPalette.inkSecondary,
                ),
              ),
              if (failure.attempt > 0) ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  failure.maxAttempts > 0
                      ? '已自动重试 ${failure.attempt}/${failure.maxAttempts} 次'
                      : '已自动重试 ${failure.attempt} 次',
                  style: const TextStyle(
                    fontSize: 12,
                    color: PlayerPalette.inkTertiary,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              _DetailToggle(
                expanded: _showDetail,
                copied: _copied,
                onToggle: () => setState(() => _showDetail = !_showDetail),
                onCopy: _copyDetail,
              ),
              if (_showDetail) ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 108),
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: PlayerPalette.panelSunken,
                    borderRadius: AppRadius.xsBR,
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      failure.rawError ?? failure.message,
                      style: const TextStyle(
                        fontSize: 11.5,
                        height: 1.5,
                        fontFamily: 'monospace',
                        color: PlayerPalette.inkTertiary,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Row(
                children: <Widget>[
                  if (widget.onExit != null)
                    _GhostButton(
                      label: '退出播放',
                      onTap: widget.onExit!,
                    ),
                  const Spacer(),
                  if (widget.onSwitchSource != null && !primaryIsSwitch)
                    _GhostButton(
                      label: '换线路',
                      icon: Icons.swap_horiz_rounded,
                      onTap: widget.onSwitchSource!,
                    ),
                  if (widget.onSwitchSource != null && !primaryIsSwitch)
                    const SizedBox(width: AppSpacing.xs),
                  _PrimaryButton(
                    label: primaryIsSwitch ? '换线路试试' : '重试',
                    icon: primaryIsSwitch
                        ? Icons.swap_horiz_rounded
                        : Icons.refresh_rounded,
                    onTap: primaryIsSwitch
                        ? widget.onSwitchSource!
                        : widget.onRetry,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _iconFor(PlaybackFailureKind kind) {
    switch (kind) {
      case PlaybackFailureKind.forbidden:
        return Icons.lock_outline_rounded;
      case PlaybackFailureKind.notFound:
        return Icons.link_off_rounded;
      case PlaybackFailureKind.parseFailed:
        return Icons.travel_explore_rounded;
      case PlaybackFailureKind.unsupported:
        return Icons.movie_filter_outlined;
      case PlaybackFailureKind.decode:
        return Icons.memory_rounded;
      case PlaybackFailureKind.timeout:
      case PlaybackFailureKind.network:
        return Icons.wifi_off_rounded;
      case PlaybackFailureKind.unknown:
        return Icons.error_outline_rounded;
    }
  }
}

class _DetailToggle extends StatelessWidget {
  const _DetailToggle({
    required this.expanded,
    required this.copied,
    required this.onToggle,
    required this.onCopy,
  });

  final bool expanded;
  final bool copied;
  final VoidCallback onToggle;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        _TextLink(
          label: expanded ? '收起技术细节' : '查看技术细节',
          onTap: onToggle,
        ),
        const SizedBox(width: AppSpacing.md),
        _TextLink(
          label: copied ? '已复制' : '复制错误信息',
          onTap: onCopy,
        ),
      ],
    );
  }
}

class _TextLink extends StatelessWidget {
  const _TextLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: PlayerPalette.inkTertiary,
              decoration: TextDecoration.underline,
              decorationColor: PlayerPalette.inkFaint,
            ),
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 9,
          ),
          decoration: BoxDecoration(
            color: PlayerPalette.accent,
            borderRadius: AppRadius.smBR,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  const _GhostButton({required this.label, required this.onTap, this.icon});

  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 9,
          ),
          decoration: BoxDecoration(
            borderRadius: AppRadius.smBR,
            border: Border.all(
              color: PlayerPalette.hairlineStrong,
              width: AppStroke.hairline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 16, color: PlayerPalette.inkSecondary),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: PlayerPalette.inkSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
