import 'package:flutter/material.dart';

import '../../../core/design/design.dart';
import '../../../domain/entities/episode.dart';
import '../../theme/player_palette.dart';
import 'player_side_sheet.dart';

/// 选集抽屉。
///
/// 交互细节
/// ------------------------------------------------------------------
/// * **当前集自动滚进视野**：40 集以上的剧集，用户打开抽屉第一件事就是
///   找"我在哪"，让他自己滚是最不体贴的做法。这里对当前集挂 `GlobalKey`
///   再用 `Scrollable.ensureVisible`，比手算行号可靠（集名长度不一会导致
///   换行位置与估算不符）。
/// * **倒序开关**：追更中的用户关心最新几集，从后往前看更顺手；补剧的用户
///   习惯正序。偏好因人而异，给开关而不是替他决定。
/// * 用 [Wrap] 而不是 `GridView`：集名长度差异大（「第 12 集」 vs
///   「番外·幕后特辑」），定宽网格会出现大片空白或大面积截断。
Future<Episode?> showEpisodeDrawer(
  BuildContext context, {
  required List<Episode> episodes,
  required int currentIndex,
  required String sourceName,
  String? title,
}) {
  if (episodes.isEmpty) return Future<Episode?>.value();

  return showPlayerSideSheet<Episode>(
    context,
    title: title ?? '选集',
    subtitle: '$sourceName · 共 ${episodes.length} 集',
    child: _EpisodeList(episodes: episodes, currentIndex: currentIndex),
  );
}

class _EpisodeList extends StatefulWidget {
  const _EpisodeList({required this.episodes, required this.currentIndex});

  final List<Episode> episodes;
  final int currentIndex;

  @override
  State<_EpisodeList> createState() => _EpisodeListState();
}

class _EpisodeListState extends State<_EpisodeList> {
  bool _descending = false;

  @override
  void initState() {
    super.initState();
    // 首帧后布局已完成，才能把当前集滚进视野。
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealCurrent());
  }

  List<Episode> get _ordered =>
      _descending ? widget.episodes.reversed.toList() : widget.episodes;

  void _revealCurrent() {
    if (!mounted) return;
    final context = _currentKey.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: AppMotion.normal,
      curve: AppMotion.standard,
      alignment: 0.3,
    );
  }

  void _toggleOrder() {
    setState(() => _descending = !_descending);
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealCurrent());
  }

  final GlobalKey _currentKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final episodes = _ordered;
    final currentInList = episodes.where((e) => e.index == widget.currentIndex);
    final currentName =
        currentInList.isEmpty ? '—' : currentInList.first.name;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _OrderBar(
          descending: _descending,
          currentName: currentName,
          onToggle: _toggleOrder,
        ),
        Expanded(
          child: Scrollbar(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.md,
                AppSpacing.lg,
              ),
              child: Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: <Widget>[
                  for (final episode in episodes)
                    _EpisodeChip(
                      key: episode.index == widget.currentIndex
                          ? _currentKey
                          : null,
                      episode: episode,
                      selected: episode.index == widget.currentIndex,
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OrderBar extends StatelessWidget {
  const _OrderBar({
    required this.descending,
    required this.currentName,
    required this.onToggle,
  });

  final bool descending;
  final String currentName;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '正在播放：$currentName',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                color: PlayerPalette.accent,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          _MiniToggle(
            label: descending ? '倒序' : '正序',
            icon: descending
                ? Icons.arrow_downward_rounded
                : Icons.arrow_upward_rounded,
            onTap: onToggle,
          ),
        ],
      ),
    );
  }
}

class _MiniToggle extends StatelessWidget {
  const _MiniToggle({
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: AppRadius.pillBR,
            border: Border.all(
              color: PlayerPalette.hairlineStrong,
              width: AppStroke.hairline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 12, color: PlayerPalette.inkTertiary),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11.5,
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

class _EpisodeChip extends StatelessWidget {
  const _EpisodeChip({
    super.key,
    required this.episode,
    required this.selected,
  });

  final Episode episode;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final playable = episode.isPlayable;

    final Color background = selected
        ? PlayerPalette.accentSoft
        : PlayerPalette.panelElevated;
    final Color border = selected
        ? PlayerPalette.accent
        : PlayerPalette.hairline;
    final Color textColor = !playable
        ? PlayerPalette.inkFaint
        : (selected ? PlayerPalette.accent : PlayerPalette.inkSecondary);

    return GestureDetector(
      onTap: playable ? () => Navigator.of(context).pop(episode) : null,
      behavior: HitTestBehavior.opaque,
      child: MouseRegion(
        cursor: playable ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: Container(
          width: 78,
          height: 38,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: background,
            borderRadius: AppRadius.xsBR,
            border: Border.all(
              color: border,
              width: selected ? AppStroke.emphasis : AppStroke.hairline,
            ),
          ),
          child: Text(
            episode.name.isEmpty ? '第 ${episode.index + 1} 集' : episode.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}
