import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/design.dart';
import '../../domain/entities/episode.dart';
import '../../domain/entities/movie.dart';
import '../../domain/entities/play_source.dart';
import '../../domain/entities/watch_record.dart';
import '../app_navigation.dart';
import '../providers/search_providers.dart';
import '../providers/watch_history_providers.dart';
import '../widgets/adaptive_scaffold.dart';
import '../widgets/poster_image.dart';
import '../widgets/section_header.dart';
import '../widgets/shimmer.dart';
import '../widgets/watch_status_button.dart';

/// 影视详情页。
///
/// 页面结构
/// ------------------------------------------------------------------
/// 1. **顶部淡化模糊背景图**：剧照自身做高斯模糊后，再叠加一层
///    浅色半透明毛玻璃蒙层与向下的渐变，使背景"淡出"融入页面底色；
/// 2. **信息区**：海报缩略图 + 标题 + 元数据标签 + 操作按钮组
///    （立即播放 / 一键追剧 / 刷新）；
/// 3. **播放面板**：线路切换 chips + 选集网格（长剧集折叠）；
/// 4. **剧情简介**。
///
/// 状态：线路与选集选择由本页持有（局部 UI 状态，无需上提到 Riverpod）；
/// 观影状态（想看 / 正在看 / 已看）与播放进度来自全局
/// [watchHistoryProvider]。
class MovieDetailPage extends ConsumerStatefulWidget {
  const MovieDetailPage({
    super.key,
    required this.sourceKey,
    required this.vodId,
    this.seed,
    this.resumeSourceFlag,
    this.resumeEpisodeIndex,
  });

  final String sourceKey;
  final String vodId;

  /// 列表页带来的轻量条目：若已含线路数据则跳过详情请求。
  final Movie? seed;

  /// 续播线路标志（来自观看记录）。
  final String? resumeSourceFlag;

  /// 续播集序号（来自观看记录）。
  final int? resumeEpisodeIndex;

  @override
  ConsumerState<MovieDetailPage> createState() => _MovieDetailPageState();
}

class _MovieDetailPageState extends ConsumerState<MovieDetailPage> {
  /// 剧集折叠阈值：超过该数量时默认收起。
  static const int _episodeCollapseThreshold = 60;

  final ScrollController _scrollController = ScrollController();

  bool _collapsed = false;
  bool _initialized = false;
  bool _episodesExpanded = false;

  int _sourceIndex = 0;
  int _episodeIndex = -1;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final collapsed = _scrollController.offset > 120;
    if (collapsed == _collapsed) return;
    setState(() => _collapsed = collapsed);
  }

  /// 首次拿到数据时按"续播记录"定位线路与集数。
  ///
  /// 直接赋值字段而不调用 setState：此时正处于 build 流程中，
  /// 赋值会被同一次 build 立即消费，无需额外帧。
  void _initializeSelection(Movie movie) {
    if (_initialized) return;
    _initialized = true;

    if (widget.resumeSourceFlag != null) {
      final index = movie.sources.indexWhere(
        (s) => s.flag == widget.resumeSourceFlag,
      );
      if (index >= 0) _sourceIndex = index;
    }
    if (widget.resumeEpisodeIndex != null) {
      _episodeIndex = widget.resumeEpisodeIndex!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = MovieRequest(
      sourceKey: widget.sourceKey,
      vodId: widget.vodId,
      seed: widget.seed,
    );
    final detailState = ref.watch(movieDetailProvider(request));

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: detailState.when(
        loading: () => _LoadingView(title: widget.seed?.title ?? '影片详情'),
        error: (error, _) => SafeArea(
          child: Column(
            children: <Widget>[
              _BackBar(title: widget.seed?.title ?? '影片详情'),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text('$error', textAlign: TextAlign.center),
                        const SizedBox(height: AppSpacing.md),
                        OutlinedButton.icon(
                          onPressed: () => ref
                              .read(movieDetailProvider(request).notifier)
                              .reload(),
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        data: (movie) {
          _initializeSelection(movie);
          return _buildBody(movie);
        },
      ),
    );
  }

  Widget _buildBody(Movie movie) {
    final layout = AppLayout.of(context);
    final bottomInset = AppScaffoldInsets.bottomOf(context);
    final usable = movie.sources.where((s) => s.hasPlayable).toList();
    final safeSourceIndex =
        usable.isEmpty ? 0 : (_sourceIndex < usable.length ? _sourceIndex : 0);
    final current = usable.isEmpty ? null : usable[safeSourceIndex];

    final backdropHeight = layout.isLargeScreen ? 340.0 : 240.0;

    return CustomScrollView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: <Widget>[
        _buildAppBar(movie, backdropHeight),

        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              layout.pagePadding,
              AppSpacing.md,
              layout.pagePadding,
              0,
            ),
            child: _InfoSection(
              movie: movie,
              compact: layout.isCompact,
              onPlay: current == null ? null : () => _playDefault(current),
              onRefresh: () =>
                  ref.read(movieDetailProvider(_request).notifier).reload(),
            ),
          ),
        ),

        SliverToBoxAdapter(
          child: SizedBox(height: layout.isLargeScreen ? 28 : 20),
        ),

        // ── 播放线路与选集 ───────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: layout.pagePadding),
            child: usable.isEmpty
                ? _NoSourceNotice(sourceName: movie.sourceName)
                : _PlayPanel(
                    sources: usable,
                    selectedSourceIndex: safeSourceIndex,
                    selectedEpisodeIndex: _episodeIndex,
                    expanded: _episodesExpanded,
                    collapseThreshold: _episodeCollapseThreshold,
                    onSelectSource: (index) => setState(() {
                      _sourceIndex = index;
                      _episodeIndex = -1;
                      _episodesExpanded = false;
                    }),
                    onSelectEpisode: (index) =>
                        setState(() => _episodeIndex = index),
                    onToggleExpand: () =>
                        setState(() => _episodesExpanded = !_episodesExpanded),
                    onPlayEpisode: (episode) => _play(
                      movie: movie,
                      source: usable[safeSourceIndex],
                      episode: episode,
                    ),
                  ),
          ),
        ),

        // ── 剧情简介 ─────────────────────────────────────
        if ((movie.description ?? '').trim().isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                layout.pagePadding,
                AppSpacing.lg,
                layout.pagePadding,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const SectionHeader(title: '剧情简介'),
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: const BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: AppRadius.cardBR,
                      border: Border.fromBorderSide(
                        BorderSide(
                          color: AppColors.hairline,
                          width: AppStroke.hairline,
                        ),
                      ),
                    ),
                    child: Text(
                      movie.description!.trim(),
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.75,
                        color: AppColors.inkSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        SliverToBoxAdapter(
          child: SizedBox(height: bottomInset + AppSpacing.xl),
        ),
      ],
    );
  }

  MovieRequest get _request => MovieRequest(
        sourceKey: widget.sourceKey,
        vodId: widget.vodId,
        seed: widget.seed,
      );

  // ── 顶部模糊背景 AppBar ─────────────────────────────────

  Widget _buildAppBar(Movie movie, double backdropHeight) {
    return SliverAppBar(
      pinned: true,
      stretch: true,
      expandedHeight: backdropHeight,
      backgroundColor: AppColors.canvas,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      // 收起后才显示标题，避免与背景上的大标题重复
      title: AnimatedOpacity(
        opacity: _collapsed ? 1 : 0,
        duration: AppMotion.fast,
        child: Text(
          movie.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.titleMedium,
        ),
      ),
      leading: const _CircleBackButton(),
      actions: <Widget>[
        _CircleIconButton(
          icon: Icons.refresh_rounded,
          tooltip: '刷新详情',
          onTap: () => ref.read(movieDetailProvider(_request).notifier).reload(),
        ),
        const SizedBox(width: AppSpacing.xs),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: _BlurredBackdrop(movie: movie),
        stretchModes: const <StretchMode>[StretchMode.zoomBackground],
      ),
    );
  }

  // ── 交互 ────────────────────────────────────────────────

  /// 播放首选线路的选集。
  ///
  /// 起始集的优先级：**本地记录里"上次在看的集" > 页面当前选中集 > 第 1 集**。
  /// 用记录优先是因为按钮文案已经写着「继续观看 · 第 3 集」——
  /// 若文案说第 3 集、点开却是第 1 集，就属于明确的自相矛盾。
  Future<void> _playDefault(PlaySource source) async {
    final movie = ref.read(movieDetailProvider(_request)).valueOrNull;
    if (movie == null) return;

    final record = ref.read(watchRecordProvider(movie.id));
    final candidate = (record != null && record.currentEpisodeIndex > 0)
        ? record.currentEpisodeIndex
        : _episodeIndex;

    final episode = source.episodeByIndex(candidate);
    if (episode == null) return;
    await _play(movie: movie, source: source, episode: episode);
  }

  /// 播放单集：交给内嵌播放页。
  ///
  /// 本方法刻意保持"薄"——只做导航，不碰播放逻辑：
  /// * **续播询问**由播放页发起（只有内核知道何时能真正 Seek）；
  /// * **会话建立 / 进度回写**由播放页的 `beginSession` +
  ///   `reportPosition` 负责（见 [PlayerPage] 的时序注释）。
  ///
  /// 这样"播放"这件事只有一个负责人：播放页。详情页不再需要
  /// 关心外部播放器是否回传进度这种无法解决的限制。
  Future<void> _play({
    required Movie movie,
    required PlaySource source,
    required Episode episode,
  }) async {
    setState(() => _episodeIndex = episode.index);
    await AppRoutes.openPlayer(
      context,
      movie: movie,
      sourceFlag: source.flag,
      episodeIndex: episode.index,
    );
  }
}

// ── 顶部背景 ────────────────────────────────────────────────

/// 淡化模糊背景 + 浅色毛玻璃蒙层。
///
/// 三层结构：
/// 1. 剧照自身高斯模糊（[ImageFiltered]）——去掉细节只保留色彩氛围；
/// 2. 浅色半透明毛玻璃层（[BackdropFilter]）——形成"磨砂玻璃"质感；
/// 3. 向下渐变至页面底色——消除背景与内容之间的硬边界。
class _BlurredBackdrop extends StatelessWidget {
  const _BlurredBackdrop({required this.movie});

  final Movie movie;

  @override
  Widget build(BuildContext context) {
    final url = (movie.backdrop ?? '').trim().isNotEmpty
        ? movie.backdrop!
        : movie.poster;

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: 28,
              sigmaY: 28,
              tileMode: TileMode.clamp,
            ),
            child: PosterImage(
              url: url,
              title: movie.title,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              placeholderIcon: Icons.local_movies_outlined,
            ),
          ),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
            child: ColoredBox(
              color: AppColors.canvas.withOpacity(0.52),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Color(0x0DF5F6F8),
                  Color(0x66F5F6F8),
                  Color(0xD9F5F6F8),
                  AppColors.canvas,
                ],
                stops: <double>[0.0, 0.42, 0.78, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 信息区 ──────────────────────────────────────────────────

class _InfoSection extends ConsumerWidget {
  const _InfoSection({
    required this.movie,
    required this.compact,
    required this.onRefresh,
    this.onPlay,
  });

  final Movie movie;
  final bool compact;
  final VoidCallback onRefresh;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = ref.watch(watchRecordProvider(movie.id));
    final resumable = record != null && record.shouldResume;

    final posterWidth = compact ? 104.0 : 186.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // 海报缩略图
        Container(
          decoration: BoxDecoration(
            borderRadius: AppRadius.cardBR,
            boxShadow: AppShadows.cardHover,
          ),
          child: ClipRRect(
            borderRadius: AppRadius.cardBR,
            child: SizedBox(
              width: posterWidth,
              height: posterWidth / AppSizes.posterAspectRatio,
              child: PosterImage(
                url: movie.poster,
                title: movie.title,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                movie.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.detailTitle.copyWith(
                  fontSize: compact ? 20 : 26,
                ),
              ),
              if ((movie.subTitle ?? '').isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  movie.subTitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.posterMeta,
                ),
              ],
              const SizedBox(height: AppSpacing.sm),

              // 元数据标签
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xxs,
                children: <Widget>[
                  if (movie.year != null) _MetaTag(text: '${movie.year}'),
                  if ((movie.area ?? '').isNotEmpty)
                    _MetaTag(text: movie.area!),
                  if ((movie.typeName ?? '').isNotEmpty)
                    _MetaTag(text: movie.typeName!, accent: true),
                  for (final c in movie.categories.take(3))
                    _MetaTag(text: c),
                  if (movie.score != null)
                    _MetaTag(
                      text: '评分 ${movie.score!.toStringAsFixed(1)}',
                      accent: true,
                    ),
                  _MetaTag(text: movie.sourceName),
                ],
              ),

              if ((movie.remarks ?? '').isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  movie.remarks!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.accent,
                  ),
                ),
              ],

              if (movie.actors.isNotEmpty && !compact) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                _InfoLine(label: '主演', value: movie.actors.take(6).join(' / ')),
              ],
              if (movie.directors.isNotEmpty && !compact)
                _InfoLine(label: '导演', value: movie.directors.join(' / ')),

              // 本地观看进度：只在真有播放行为时出现，
              // 让用户一眼看到「上次看到哪」而不必点进播放器
              if (record != null && record.hasProgress)
                _InfoLine(
                  label: '观看进度',
                  value: record.totalDurationMs > 0
                      ? '${record.progressLabel} · '
                          '剩余 ${WatchRecord.formatDuration(record.remainingMs)}'
                      : record.progressLabel,
                ),

              const SizedBox(height: AppSpacing.md),

              // 操作按钮组
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: <Widget>[
                  FilledButton.icon(
                    onPressed: onPlay,
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: Text(
                      resumable ? '继续观看 · ${record.episodeLabel}' : '立即播放',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      elevation: 0,
                      shadowColor: Colors.transparent,
                    ),
                  ),
                  // 三态入口：想看 / 正在看 / 已看 / 移出片库
                  WatchStatusButton(
                    movie: movie,
                    onChanged: (next) => _notifyStatus(context, next),
                  ),
                  OutlinedButton.icon(
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('刷新'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 状态切换后的轻提示。
  ///
  /// 菜单关闭即完成动作，若不给反馈，用户无法确认是否真的生效
  /// （尤其是"移出片库"这种无视觉残留的操作）。
  static void _notifyStatus(BuildContext context, WatchStatus? next) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          switch (next) {
            WatchStatus.wantToWatch => '已加入「想看」',
            WatchStatus.watching => '已标记为「正在看」',
            WatchStatus.watched => '已标记为「已看」',
            null => '已移出我的片库',
          },
        ),
      ),
    );
  }
}

class _MetaTag extends StatelessWidget {
  const _MetaTag({required this.text, this.accent = false});

  final String text;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: accent ? AppColors.accentSoft : AppColors.surface,
        borderRadius: AppRadius.xsBR,
        border: Border.all(
          color: accent ? AppColors.accentSoft : AppColors.hairline,
          width: AppStroke.hairline,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
          color: accent ? AppColors.accent : AppColors.inkSecondary,
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: RichText(
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          style: const TextStyle(fontSize: 12.5, height: 1.5),
          children: <TextSpan>[
            TextSpan(
              text: '$label  ',
              style: const TextStyle(
                color: AppColors.inkTertiary,
                fontWeight: FontWeight.w500,
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(color: AppColors.inkSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 播放面板 ────────────────────────────────────────────────

class _PlayPanel extends StatelessWidget {
  const _PlayPanel({
    required this.sources,
    required this.selectedSourceIndex,
    required this.selectedEpisodeIndex,
    required this.expanded,
    required this.collapseThreshold,
    required this.onSelectSource,
    required this.onSelectEpisode,
    required this.onToggleExpand,
    required this.onPlayEpisode,
  });

  final List<PlaySource> sources;
  final int selectedSourceIndex;
  final int selectedEpisodeIndex;
  final bool expanded;
  final int collapseThreshold;
  final ValueChanged<int> onSelectSource;
  final ValueChanged<int> onSelectEpisode;
  final VoidCallback onToggleExpand;
  final ValueChanged<Episode> onPlayEpisode;

  @override
  Widget build(BuildContext context) {
    final source = sources[selectedSourceIndex];
    final all = source.episodes;
    final shouldCollapse = all.length > collapseThreshold && !expanded;
    final visible = shouldCollapse
        ? all.take(collapseThreshold).toList(growable: false)
        : all;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(
          title: '播放线路',
          subtitle: '${sources.length} 条线路 · 共 ${all.length} 集',
        ),
        const SizedBox(height: AppSpacing.sm),

        // 线路切换
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: <Widget>[
            for (var i = 0; i < sources.length; i++)
              _LineChip(
                source: sources[i],
                selected: i == selectedSourceIndex,
                onTap: () => onSelectSource(i),
              ),
          ],
        ),

        const SizedBox(height: AppSpacing.lg),
        Row(
          children: <Widget>[
            const Text('选集', style: AppTypography.sectionTitle),
            const SizedBox(width: AppSpacing.xs),
            Text(
              '${all.length} 集',
              style: AppTypography.posterMeta,
            ),
            const Spacer(),
            if (all.length > collapseThreshold)
              TextButton(
                onPressed: onToggleExpand,
                child: Text(expanded ? '收起' : '展开全部'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),

        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: <Widget>[
            for (final episode in visible)
              _EpisodeButton(
                episode: episode,
                selected: episode.index == selectedEpisodeIndex,
                onTap: () {
                  onSelectEpisode(episode.index);
                  onPlayEpisode(episode);
                },
              ),
          ],
        ),
      ],
    );
  }
}

/// 线路切换 chip：显示线路名、集数与可用状态。
class _LineChip extends StatefulWidget {
  const _LineChip({
    required this.source,
    required this.selected,
    required this.onTap,
  });

  final PlaySource source;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_LineChip> createState() => _LineChipState();
}

class _LineChipState extends State<_LineChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.standard,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accentSoft
                : (_hovered ? AppColors.surfaceMuted : AppColors.surface),
            borderRadius: AppRadius.smBR,
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.hairline,
              width: selected ? AppStroke.emphasis : AppStroke.hairline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 14,
                color: selected ? AppColors.accent : AppColors.inkDisabled,
              ),
              const SizedBox(width: 5),
              Text(
                widget.source.name,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? AppColors.accent : AppColors.inkSecondary,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                '${widget.source.episodeCount}集',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.inkDisabled,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 选集按钮：等宽网格化排布，hover 微浮起，选中态描边强调。
class _EpisodeButton extends StatefulWidget {
  const _EpisodeButton({
    required this.episode,
    required this.selected,
    required this.onTap,
  });

  final Episode episode;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_EpisodeButton> createState() => _EpisodeButtonState();
}

class _EpisodeButtonState extends State<_EpisodeButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final playable = widget.episode.isPlayable;
    final selected = widget.selected;

    final Color background;
    final Color border;
    final Color foreground;

    if (selected) {
      background = AppColors.accent;
      border = AppColors.accent;
      foreground = AppColors.inkOnDark;
    } else if (!playable) {
      background = AppColors.surfaceMuted;
      border = AppColors.hairline;
      foreground = AppColors.inkDisabled;
    } else {
      background = _hovered ? AppColors.accentSofter : AppColors.surface;
      border = _hovered ? AppColors.accentSoft : AppColors.hairline;
      foreground = AppColors.inkSecondary;
    }

    return MouseRegion(
      cursor: playable ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: playable ? widget.onTap : null,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.standard,
          transform: Matrix4.translationValues(
            0,
            _hovered && playable && !selected ? -2 : 0,
            0,
          ),
          width: 86,
          height: 38,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: background,
            borderRadius: AppRadius.smBR,
            border: Border.all(
              color: border,
              width: selected ? AppStroke.emphasis : AppStroke.hairline,
            ),
            boxShadow: _hovered && playable && !selected
                ? AppShadows.card
                : null,
          ),
          child: Text(
            widget.episode.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppTypography.episode.copyWith(color: foreground),
          ),
        ),
      ),
    );
  }
}

class _NoSourceNotice extends StatelessWidget {
  const _NoSourceNotice({required this.sourceName});

  final String sourceName;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardBR,
        border: Border.fromBorderSide(
          BorderSide(color: AppColors.hairline, width: AppStroke.hairline),
        ),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: AppColors.warning,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '「$sourceName」暂未返回可播放线路。\n可返回搜索结果切换其它数据源查看。',
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.6,
                color: AppColors.inkSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 顶部按钮 ────────────────────────────────────────────────

/// 圆形毛玻璃返回按钮（保证在任何背景图上都可见）。
class _CircleBackButton extends StatelessWidget {
  const _CircleBackButton();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: _CircleIconButton(
        icon: Icons.arrow_back_rounded,
        tooltip: '返回',
        onTap: () => Navigator.of(context).maybePop(),
      ),
    );
  }
}

class _CircleIconButton extends StatefulWidget {
  const _CircleIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  State<_CircleIconButton> createState() => _CircleIconButtonState();
}

class _CircleIconButtonState extends State<_CircleIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final button = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _hovered
                ? AppColors.surface
                : AppColors.surface.withOpacity(0.80),
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.hairline,
              width: AppStroke.hairline,
            ),
            boxShadow: AppShadows.card,
          ),
          child: Icon(widget.icon, size: 18, color: AppColors.ink),
        ),
      ),
    );

    if (widget.tooltip == null) return button;
    return Tooltip(message: widget.tooltip!, child: button);
  }
}

class _BackBar extends StatelessWidget {
  const _BackBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: <Widget>[
          const _CircleBackButton(),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.titleMedium,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 加载态 ──────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final layout = AppLayout.of(context);
    final backdropHeight = layout.isLargeScreen ? 340.0 : 240.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SafeArea(bottom: false, child: _BackBar(title: '加载中…')),
        // 背景骨架
        Padding(
          padding: EdgeInsets.symmetric(horizontal: layout.pagePadding),
          child: Shimmer(
            child: Container(
              height: backdropHeight - 60,
              decoration: const BoxDecoration(
                color: AppColors.skeletonBase,
                borderRadius: AppRadius.panelBR,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        // 信息区骨架
        Padding(
          padding: EdgeInsets.symmetric(horizontal: layout.pagePadding),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Shimmer(
                child: Container(
                  width: layout.isCompact ? 104 : 186,
                  height: (layout.isCompact ? 104 : 186) /
                      AppSizes.posterAspectRatio,
                  decoration: const BoxDecoration(
                    color: AppColors.skeletonBase,
                    borderRadius: AppRadius.cardBR,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SkeletonBox(width: 220, height: 22),
                    SizedBox(height: AppSpacing.sm),
                    SkeletonBox(width: 160, height: 12),
                    SizedBox(height: AppSpacing.md),
                    SkeletonBox(width: 260, height: 12),
                    SizedBox(height: AppSpacing.xs),
                    SkeletonBox(width: 200, height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: layout.pagePadding),
          child: const TextBlockSkeleton(lines: 4),
        ),
      ],
    );
  }
}
