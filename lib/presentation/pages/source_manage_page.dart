import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/design.dart';
import '../../core/error/failure.dart';
import '../../domain/entities/source_config.dart';
import '../../domain/entities/source_validation.dart';
import '../providers/core_providers.dart';
import '../providers/home_providers.dart';
import '../providers/source_providers.dart';
import '../widgets/adaptive_scaffold.dart';
import '../widgets/empty_state.dart';
import '../widgets/shimmer.dart';

/// 数据源管理页。
///
/// 定位：这是「客户端不内置任何爬虫」这一架构决策的**用户侧入口**——
/// 所有数据源都通过订阅导入与热更新获得。
///
/// 状态可视化：每个源用一枚健康度指示灯表示校验结果
/// （绿=可用 / 橙=降级 / 红=不可达 / 灰=未校验），
/// 校验同时展示延迟与"样本标题"，供用户判断源站内容是否对版。
class SourceManagePage extends ConsumerWidget {
  const SourceManagePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = AppLayout.of(context);
    final sourcesState = ref.watch(sourcesProvider);
    final validationMap = ref.watch(bulkValidationProvider);
    final subscriptions = ref.watch(subscriptionsProvider).valueOrNull ??
        const <SourceSubscription>[];
    final bottomInset = AppScaffoldInsets.bottomOf(context);
    final validating = ref.watch(validatingProvider);

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: <Widget>[
        // ── 头部 ─────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              layout.pagePadding,
              layout.isDesktop
                  ? AppSpacing.md
                  : MediaQuery.paddingOf(context).top + AppSpacing.sm,
              layout.pagePadding,
              AppSpacing.sm,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text('数据源', style: AppTypography.headlineSmall),
                      SizedBox(height: 2),
                      Text(
                        '订阅导入 · 可用性校验 · 热更新',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.inkTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: validating
                      ? null
                      : () => _validateAll(context, ref),
                  icon: validating
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.health_and_safety_outlined, size: 16),
                  label: Text(validating ? '校验中…' : '校验全部'),
                ),
                const SizedBox(width: AppSpacing.xs),
                FilledButton.icon(
                  onPressed: () => _showImportDialog(context, ref),
                  icon: const Icon(Icons.add_link, size: 16),
                  label: const Text('导入订阅'),
                ),
              ],
            ),
          ),
        ),

        // ── 订阅区 ───────────────────────────────────────
        if (subscriptions.isNotEmpty)
          SliverToBoxAdapter(
            child: _SubscriptionsSection(subscriptions: subscriptions),
          ),

        // ── 统计条 ───────────────────────────────────────
        if (sourcesState.valueOrNull?.isNotEmpty ?? false)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                layout.pagePadding,
                AppSpacing.sm,
                layout.pagePadding,
                AppSpacing.xs,
              ),
              child: Text(
                '共 ${sourcesState.value!.length} 个源 · '
                '启用 ${sourcesState.value!.where((s) => s.enabled).length} 个 · '
                '已校验 ${validationMap.length} 个',
                style: AppTypography.posterMeta,
              ),
            ),
          ),

        // ── 源列表 ───────────────────────────────────────
        ...sourcesState.when(
          loading: () => <Widget>[
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: layout.pagePadding),
                child: const TextBlockSkeleton(lines: 5, lineHeight: 22),
              ),
            ),
          ],
          error: (error, _) => <Widget>[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                child: ErrorView(
                  message: '$error',
                  onRetry: () => ref.read(sourcesProvider.notifier).reload(),
                ),
              ),
            ),
          ],
          data: (sources) {
            if (sources.isEmpty) {
              return <Widget>[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: layout.pagePadding,
                      vertical: AppSpacing.xxl,
                    ),
                    child: EmptyState(
                      icon: Icons.dns_outlined,
                      title: '还没有任何数据源',
                      description:
                          'MovieHub 不内置任何站点采集逻辑。\n'
                          '导入一份订阅包（JSON）即可获得可热更新的数据源集合。',
                      action: FilledButton.icon(
                        onPressed: () => _showImportDialog(context, ref),
                        icon: const Icon(Icons.add_link, size: 16),
                        label: const Text('导入订阅'),
                      ),
                    ),
                  ),
                ),
              ];
            }

            return <Widget>[
              SliverList.builder(
                itemCount: sources.length,
                itemBuilder: (context, index) {
                  final config = sources[index];
                  return Padding(
                    padding: EdgeInsets.fromLTRB(
                      layout.pagePadding,
                      0,
                      layout.pagePadding,
                      AppSpacing.xs,
                    ),
                    child: _SourceTile(
                      config: config,
                      validation: validationMap[config.key],
                    ),
                  );
                },
              ),
            ];
          },
        ),

        SliverToBoxAdapter(
          child: SizedBox(height: bottomInset + AppSpacing.xl),
        ),
      ],
    );
  }

  Future<void> _validateAll(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final sources =
        ref.read(sourcesProvider).valueOrNull ?? const <SourceConfig>[];
    final supported =
        sources.where((s) => s.kind.isClientSupported).toList(growable: false);
    if (supported.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('没有可校验的数据源')));
      return;
    }

    ref.read(validatingProvider.notifier).state = true;
    try {
      final results = await ref.read(sourceManagerProvider).validateAll(supported);
      ref.read(bulkValidationProvider.notifier).state = results;

      final healthy =
          results.values.where((r) => r.health == SourceHealth.healthy).length;
      final degraded = results.values
          .where((r) => r.health == SourceHealth.degraded)
          .length;
      final unreachable = results.values
          .where((r) => r.health == SourceHealth.unreachable)
          .length;

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '校验完成：可用 $healthy · 降级 $degraded · 不可达 $unreachable',
          ),
        ),
      );
    } finally {
      ref.read(validatingProvider.notifier).state = false;
    }
  }

  Future<void> _showImportDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final layout = AppLayout.of(context);

    final url = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadius.panelBR,
        ),
        title: const Text('导入数据源订阅', style: AppTypography.titleMedium),
        content: SizedBox(
          width: layout.isDesktop ? 460 : double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                '支持本协议订阅包（moviehub/v1）与 TVBox 生态订阅（sites 数组）。'
                '导入后配置保存在本机，订阅更新时可一键热更新，无需升级客户端。',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.6,
                  color: AppColors.inkTertiary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'https://example.com/moviehub-sub.json',
                  prefixIcon: Icon(Icons.link_rounded, size: 18),
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('导入'),
          ),
        ],
      ),
    );

    if (url == null || url.isEmpty) return;
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final report = await ref.read(sourcesProvider.notifier).importFromUrl(url);
      // 数据源变化 → 首页需要重新装配
      ref.invalidate(homeFeedProvider);
      messenger.showSnackBar(SnackBar(content: Text('导入成功：${report.summary}')));
    } on Failure catch (failure) {
      messenger.showSnackBar(
        SnackBar(content: Text('导入失败：${failure.message}')),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('导入失败：$error')));
    }
  }
}

/// 全局校验中标志（避免重复点击）。
final validatingProvider = StateProvider<bool>((ref) => false);

// ── 单个数据源卡片 ──────────────────────────────────────────

class _SourceTile extends ConsumerStatefulWidget {
  const _SourceTile({required this.config, this.validation});

  final SourceConfig config;
  final SourceValidationResult? validation;

  @override
  ConsumerState<_SourceTile> createState() => _SourceTileState();
}

class _SourceTileState extends ConsumerState<_SourceTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final validation = widget.validation;
    final unsupported = !config.kind.isClientSupported;
    final perSource =
        ref.watch(sourceValidationProvider(config)).valueOrNull ?? validation;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.standard,
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.cardBR,
          border: Border.all(
            color: _hovered ? AppColors.hairlineStrong : AppColors.hairline,
            width: AppStroke.hairline,
          ),
          boxShadow: _hovered ? AppShadows.card : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _HealthDot(health: perSource?.health),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          config.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.posterTitle.copyWith(
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      _Tag(text: config.kind.wire),
                      const SizedBox(width: AppSpacing.xxs),
                      _Tag(text: 'P${config.priority}'),
                      if (unsupported) ...<Widget>[
                        const SizedBox(width: AppSpacing.xxs),
                        _Tag(text: '不支持', danger: true),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    config.api.isEmpty ? '（未配置地址）' : config.api,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.inkTertiary,
                    ),
                  ),
                  if (perSource != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      _validationText(perSource),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.5,
                        color: perSource.health.isError
                            ? AppColors.danger
                            : AppColors.inkTertiary,
                      ),
                    ),
                  ],
                  if (config.comment != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      config.comment!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.inkDisabled,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Tooltip(
                  message: '校验可用性',
                  child: _MiniIconButton(
                    icon: Icons.refresh_rounded,
                    onTap: () => ref
                        .read(sourceValidationProvider(config).notifier)
                        .run(),
                  ),
                ),
                Switch(
                  value: config.enabled,
                  activeColor: AppColors.accent,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: unsupported
                      ? null
                      : (value) => ref
                          .read(sourcesProvider.notifier)
                          .toggle(config.key, value),
                ),
              ],
            ),
            _MoreMenu(config: config),
          ],
        ),
      ),
    );
  }

  static String _validationText(SourceValidationResult result) {
    final parts = <String>[
      result.health.label,
      '${result.latencyMs}ms',
      if (result.sampleCount > 0) '${result.sampleCount} 条样本',
      if ((result.sampleTitle ?? '').isNotEmpty) '「${result.sampleTitle}」',
      if ((result.message ?? '').isNotEmpty) result.message!,
    ];
    return parts.join(' · ');
  }
}

class _MoreMenu extends ConsumerWidget {
  const _MoreMenu({required this.config});

  final SourceConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: const Icon(
        Icons.more_vert_rounded,
        size: 18,
        color: AppColors.inkTertiary,
      ),
      tooltip: '更多操作',
      onSelected: (value) {
        final notifier = ref.read(sourcesProvider.notifier);
        if (value == 'priority_up') {
          final next = config.priority - 10;
          notifier.setPriority(config.key, next < 0 ? 0 : next);
        } else if (value == 'priority_down') {
          notifier.setPriority(config.key, config.priority + 10);
        } else if (value == 'delete') {
          notifier.remove(config.key);
          ref.invalidate(homeFeedProvider);
        }
      },
      itemBuilder: (_) => const <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'priority_up',
          child: Text('提高优先级'),
        ),
        PopupMenuItem<String>(
          value: 'priority_down',
          child: Text('降低优先级'),
        ),
        PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'delete',
          child: Text('删除该源', style: TextStyle(color: AppColors.danger)),
        ),
      ],
    );
  }
}

class _HealthDot extends StatelessWidget {
  const _HealthDot({this.health});

  final SourceHealth? health;

  @override
  Widget build(BuildContext context) {
    final color = _color(Theme.of(context).colorScheme);
    return Container(
      width: 10,
      height: 10,
      margin: const EdgeInsets.only(top: 5),
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: <BoxShadow>[
          BoxShadow(color: color.withOpacity(0.28), blurRadius: 6, spreadRadius: 1),
        ],
      ),
    );
  }

  Color _color(ColorScheme scheme) {
    final value = health;
    if (value == SourceHealth.healthy) return AppColors.positive;
    if (value == SourceHealth.degraded) return AppColors.warning;
    if (value == SourceHealth.unreachable) return AppColors.danger;
    if (value == SourceHealth.invalid) return scheme.error;
    return AppColors.inkDisabled;
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, this.danger = false});

  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: danger ? AppColors.dangerSoft : AppColors.surfaceMuted,
        borderRadius: AppRadius.xsBR,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w500,
          color: danger ? AppColors.danger : AppColors.inkTertiary,
        ),
      ),
    );
  }
}

class _MiniIconButton extends StatefulWidget {
  const _MiniIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_MiniIconButton> createState() => _MiniIconButtonState();
}

class _MiniIconButtonState extends State<_MiniIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMotion.instant,
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: _hovered ? AppColors.accentSofter : Colors.transparent,
            borderRadius: AppRadius.xsBR,
          ),
          child: Icon(
            widget.icon,
            size: 17,
            color: _hovered ? AppColors.accent : AppColors.inkTertiary,
          ),
        ),
      ),
    );
  }
}

// ── 订阅区 ──────────────────────────────────────────────────

class _SubscriptionsSection extends ConsumerStatefulWidget {
  const _SubscriptionsSection({required this.subscriptions});

  final List<SourceSubscription> subscriptions;

  @override
  ConsumerState<_SubscriptionsSection> createState() =>
      _SubscriptionsSectionState();
}

class _SubscriptionsSectionState extends ConsumerState<_SubscriptionsSection> {
  bool _checking = false;

  @override
  Widget build(BuildContext context) {
    final layout = AppLayout.of(context);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: layout.pagePadding),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.cardBR,
          border: Border.fromBorderSide(
            BorderSide(color: AppColors.hairline, width: AppStroke.hairline),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(
                  Icons.rss_feed_rounded,
                  size: 16,
                  color: AppColors.inkTertiary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  '已导入订阅（${widget.subscriptions.length}）',
                  style: AppTypography.posterTitle.copyWith(fontSize: 13.5),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _checking ? null : _checkUpdates,
                  icon: _checking
                      ? const SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync_rounded, size: 15),
                  label: Text(_checking ? '检查中…' : '检查更新'),
                ),
              ],
            ),
            for (final sub in widget.subscriptions)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            sub.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: AppColors.ink,
                            ),
                          ),
                          Text(
                            'v${sub.version} · '
                            '${sub.url.isEmpty ? '本地导入' : sub.url}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.inkTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => _refresh(sub),
                      child: const Text('更新'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _checkUpdates() async {
    setState(() => _checking = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updates =
          await ref.read(subscriptionsProvider.notifier).checkUpdates();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            updates == 0 ? '全部订阅均为最新' : '发现 $updates 个订阅有新版本',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _refresh(SourceSubscription sub) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final report =
          await ref.read(subscriptionsProvider.notifier).refresh(sub.id);
      ref.invalidate(homeFeedProvider);
      messenger.showSnackBar(SnackBar(content: Text('更新完成：${report.summary}')));
    } on Failure catch (failure) {
      messenger.showSnackBar(SnackBar(content: Text('更新失败：${failure.message}')));
    }
  }
}
