import 'package:flutter/material.dart';

import '../../../core/design/design.dart';
import '../../../domain/entities/play_source.dart';
import '../../theme/player_palette.dart';
import 'player_side_sheet.dart';

/// 线路切换抽屉。
///
/// 为什么线路信息要展示得这么细
/// ------------------------------------------------------------------
/// 同一部影片的各条线路画质与稳定性差异极大，而用户只能靠"名字"猜。
/// 因此每条线路都尽量给出**可判断的事实**：
/// * `集数` —— 更新进度（少的说明还没更新完）；
/// * `直链` 比例 —— 是否可被本客户端直接播放（需解析的线路注定失败）；
/// * `当前线路` 标记 + 那一集在新线路上的对应集名 ——
///   让用户知道切过去会跳到哪一集（各线路的集名并不一致）。
///
/// 切换语义
/// ------------------------------------------------------------------
/// 返回用户选中的 [PlaySource]，**由播放页负责重建会话**：
/// 切线路 = 开一个新的 [beginSession]（进度归零或沿用由页面按集号判定）。
/// 抽屉本身不碰播放器。
Future<PlaySource?> showSourceDrawer(
  BuildContext context, {
  required List<PlaySource> sources,
  required String? currentFlag,
  int? currentEpisodeIndex,
}) {
  if (sources.isEmpty) return Future<PlaySource?>.value();

  return showPlayerSideSheet<PlaySource>(
    context,
    title: '切换线路',
    subtitle: '共 ${sources.length} 条线路 · 切换后从对应集继续',
    child: _SourceList(
      sources: sources,
      currentFlag: currentFlag,
      currentEpisodeIndex: currentEpisodeIndex,
    ),
  );
}

class _SourceList extends StatelessWidget {
  const _SourceList({
    required this.sources,
    required this.currentFlag,
    required this.currentEpisodeIndex,
  });

  final List<PlaySource> sources;
  final String? currentFlag;
  final int? currentEpisodeIndex;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      itemCount: sources.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.xs),
      itemBuilder: (context, index) {
        final source = sources[index];
        return _SourceTile(
          source: source,
          selected: source.flag == currentFlag,
          currentEpisodeIndex: currentEpisodeIndex,
        );
      },
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.source,
    required this.selected,
    required this.currentEpisodeIndex,
  });

  final PlaySource source;
  final bool selected;
  final int? currentEpisodeIndex;

  /// 该线路在"当前这一集"上的对应集名。
  ///
  /// 各线路集名与排序并不一致，直接按 index 取既简单又符合直觉：
  /// 用户想的是"我在看第 12 集"，而不是"我在看某个 URL"。
  String? get _correspondingEpisodeName {
    final index = currentEpisodeIndex;
    if (index == null || index < 0) return null;
    for (final episode in source.episodes) {
      if (episode.index == index) return episode.name;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final playable = source.episodes.where((e) => e.isPlayable).length;
    final direct = source.episodes.where((e) => e.isDirectMedia).length;
    final directRatio = playable == 0 ? 0 : (direct / playable * 100).round();
    final target = _correspondingEpisodeName;

    return GestureDetector(
      onTap: () => Navigator.of(context).pop(source),
      behavior: HitTestBehavior.opaque,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: selected ? PlayerPalette.accentSoft : PlayerPalette.panelElevated,
            borderRadius: AppRadius.smBR,
            border: Border.all(
              color: selected ? PlayerPalette.accent : PlayerPalette.hairline,
              width: selected ? AppStroke.emphasis : AppStroke.hairline,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            source.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: selected
                                  ? PlayerPalette.accent
                                  : PlayerPalette.ink,
                            ),
                          ),
                        ),
                        if (selected) ...<Widget>[
                          const SizedBox(width: 6),
                          const _Badge(
                            label: '当前',
                            color: PlayerPalette.accent,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${source.episodeCount} 集 · 可播 $playable · 直链 $directRatio%',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: PlayerPalette.inkTertiary,
                      ),
                    ),
                    if (target != null && !selected) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        '切到第 ${(currentEpisodeIndex ?? 0) + 1} 集（$target）',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: PlayerPalette.inkFaint,
                        ),
                      ),
                    ],
                    if (playable == 0) ...<Widget>[
                      const SizedBox(height: 4),
                      const Text(
                        '该线路暂无可用播放地址',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: PlayerPalette.warning,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(
                selected ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
                size: selected ? 18 : 20,
                color: selected
                    ? PlayerPalette.accent
                    : PlayerPalette.inkFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: AppRadius.xsBR,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
