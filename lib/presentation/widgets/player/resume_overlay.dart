import 'package:flutter/material.dart';

import '../../../core/design/design.dart';
import '../../../domain/entities/watch_record.dart';
import '../../theme/player_palette.dart';

/// 续播询问的结果。
enum ResumeChoice {
  /// 从上次的位置继续。
  resume,

  /// 从头开始。
  restart,

  /// 取消（什么都不做 / 退出播放页）。
  cancel,
}

/// 是否需要弹出续播询问。
///
/// 判据集中在 [WatchRecord.shouldResume]：有实际进度、且未达到完成阈值。
/// 这样"刚点开就退出"与"已经看完"两种噪声都不会打扰用户。
bool shouldPromptResume(WatchRecord? record) =>
    record != null && record.shouldResume;

/// 播放页内的续播浮层（暗色）。
///
/// 为什么不再用浅色弹窗
/// ------------------------------------------------------------------
/// 续播询问只在**播放页内**出现，而播放页此刻画面可能正在播上一集的尾声，
/// 一个纯白弹窗会突兀地打断沉浸感；而且浅色弹窗的对比度是基于
/// `#F5F6F8` 底色设计的，落在黑色视频上会显得"外挂"。
/// 因此这里用播放层自己的暗色体系重做，判定逻辑与返回值则完全沿用。
///
/// 一键续播
/// ------------------------------------------------------------------
/// 浮层本身**不执行 Seek**，只返回用户的选择。Seek 由播放页把
/// `record.lastPositionMs` 写进 `PlaybackSource.startPositionMs`，
/// 再由内核在拿到时长后执行 —— 内核对 open 完成前的 Seek 会直接丢弃，
/// 这一点必须在调用链上明确，否则续播会"偶尔失效"。
Future<ResumeChoice> showPlayerResumeOverlay(
  BuildContext context, {
  required WatchRecord record,
}) async {
  final choice = await showGeneralDialog<ResumeChoice>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '继续播放',
    barrierColor: const Color(0x8C000000),
    transitionDuration: AppMotion.normal,
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (dialogContext, animation, _, __) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppMotion.standard,
        reverseCurve: AppMotion.soft,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: _ResumeCard(record: record),
        ),
      );
    },
  );
  // 点遮罩 / 返回键 = 取消，避免"误关浮层却直接起播"。
  return choice ?? ResumeChoice.cancel;
}

class _ResumeCard extends StatelessWidget {
  const _ResumeCard({required this.record});

  final WatchRecord record;

  @override
  Widget build(BuildContext context) {
    final percent = record.percentInt;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Container(
          margin: const EdgeInsets.all(AppSpacing.lg),
          padding: const EdgeInsets.all(AppSpacing.lg),
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
                blurRadius: 26,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                '继续播放？',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: PlayerPalette.ink,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                record.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                  color: PlayerPalette.inkSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  Text(
                    '上次观看到 ${WatchRecord.formatDuration(record.lastPositionMs)}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: PlayerPalette.accent,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    record.episodeLabel,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: PlayerPalette.inkTertiary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              _ProgressLine(
                percent: percent,
                trailing: record.remainingMs > 0
                    ? '剩余 ${WatchRecord.formatDuration(record.remainingMs)}'
                    : '已看 $percent%',
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _SecondaryAction(
                      label: '从头播放',
                      onTap: () =>
                          Navigator.of(context).pop(ResumeChoice.restart),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _PrimaryAction(
                      label: '一键续播',
                      onTap: () =>
                          Navigator.of(context).pop(ResumeChoice.resume),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.percent, required this.trailing});

  final int percent;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    final fraction = percent / 100;
    return Row(
      children: <Widget>[
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              height: 3,
              child: Stack(
                children: <Widget>[
                  const Positioned.fill(
                    child: ColoredBox(color: PlayerPalette.track),
                  ),
                  Positioned.fill(
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: fraction < 0 ? 0 : (fraction > 1 ? 1 : fraction),
                      child: const ColoredBox(color: PlayerPalette.accent),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          trailing,
          style: const TextStyle(
            fontSize: 12,
            color: PlayerPalette.inkTertiary,
          ),
        ),
      ],
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: PlayerPalette.accent,
            borderRadius: AppRadius.smBR,
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _SecondaryAction extends StatelessWidget {
  const _SecondaryAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: AppRadius.smBR,
            border: Border.all(
              color: PlayerPalette.hairlineStrong,
              width: AppStroke.hairline,
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: PlayerPalette.inkSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
