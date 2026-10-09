import 'dart:async';

import 'package:collection/collection.dart';

import '../../core/constants/app_constants.dart';
import '../../core/error/exceptions.dart';
import '../../core/network/http_service.dart';
import '../../core/utils/semaphore.dart';
import '../../domain/entities/source_config.dart';
import '../../domain/entities/source_validation.dart';
import '../../domain/repositories/source_repository.dart';
import '../../domain/usecases/manage_sources_usecase.dart';
import '../mappers/failure_mapper.dart';
import '../parsers/parser_registry.dart';
import 'search_aggregator.dart';

/// 热更新合并策略。
class MergePolicy {
  const MergePolicy({
    this.preserveUserOverrides = true,
    this.importDisabledSources = true,
    this.replaceExisting = true,
  });

  /// 保留用户在本地的开关与优先级设置（不被订阅包覆盖）。
  /// 这是**必要的**——否则每次订阅更新都会把用户手动关闭的广告源重新打开。
  final bool preserveUserOverrides;

  /// 是否导入订阅中标记为 `enabled:false` 的源（通常仍导入但保持禁用）。
  final bool importDisabledSources;

  /// 对已存在的 key，是否用订阅内容覆盖配置主体。
  final bool replaceExisting;
}

/// 数据源管理服务。
///
/// 承担四类职责：
/// 1. **添加**：从订阅 URL / 原始 JSON 文本导入数据源（含协议版本校验）；
/// 2. **解析**：把外部订阅（含 TVBox 生态格式）翻译为内部 [SourceConfig]；
/// 3. **校验**：通过真实探针调用判定源的可用性，输出 [SourceValidationResult]；
/// 4. **热更新**：基于 version / ETag 的增量合并，保留用户本地覆盖项。
///
/// 全流程异常捕获：所有对外方法要么返回结果对象，要么抛出 [Failure] 子类。
class SourceManager implements ManageSourcesUseCase {
  SourceManager({
    required SourceRepository repository,
    required SearchAggregator aggregator,
    required ParserRegistry registry,
    required HttpService http,
    Semaphore? validationGate,
  })  : _repository = repository,
        _aggregator = aggregator,
        _registry = registry,
        _http = http,
        _validationGate = validationGate ?? Semaphore(5);

  final SourceRepository _repository;
  final SearchAggregator _aggregator;
  final ParserRegistry _registry;
  final HttpService _http;
  final Semaphore _validationGate;

  /// 超过该延迟判定为「降级」。
  static const int _slowThresholdMs = 5000;

  // ── 查询 ────────────────────────────────────────────────

  /// 读取全部数据源，按优先级排序。
  Future<List<SourceConfig>> loadSources({bool enabledOnly = false}) async {
    try {
      final sources = await _repository.loadSources();
      final list = enabledOnly
          ? sources.where((s) => s.enabled).toList()
          : List<SourceConfig>.from(sources);
      list.sort((a, b) => a.priority.compareTo(b.priority));
      return list;
    } catch (error) {
      throw FailureMapper.map(error);
    }
  }

  Future<List<SourceSubscription>> loadSubscriptions() async {
    try {
      return await _repository.loadSubscriptions();
    } catch (error) {
      throw FailureMapper.map(error);
    }
  }

  // ── 添加 / 导入 ─────────────────────────────────────────

  /// 从订阅地址导入。
  ///
  /// 流程：拉取 → 协议版本校验 → 逐源配置校验 → 与本地合并 → 持久化。
  Future<SourceImportReport> importFromUrl(
    String url, {
    MergePolicy policy = const MergePolicy(),
  }) async {
    final normalized = url.trim();
    if (normalized.isEmpty) {
      throw const SourceConfigException('订阅地址不能为空');
    }
    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw SourceConfigException('订阅地址不是合法的 URL：$normalized');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw SourceConfigException('订阅地址必须使用 http/https 协议');
    }

    final SourceSubscription subscription;
    try {
      subscription = await _repository.fetchSubscription(normalized);
    } catch (error) {
      throw FailureMapper.map(error);
    }

    return _mergeAndPersist(subscription, policy: policy);
  }

  /// 从原始 JSON 文本导入（本地文件 / 剪贴板）。
  Future<SourceImportReport> importFromRaw(
    String rawJson, {
    String url = '',
    MergePolicy policy = const MergePolicy(),
  }) async {
    if (rawJson.trim().isEmpty) {
      throw const SourceConfigException('订阅内容为空');
    }
    final SourceSubscription subscription;
    try {
      subscription = _repository.parseSubscription(rawJson, url: url);
    } catch (error) {
      throw FailureMapper.map(error);
    }
    return _mergeAndPersist(subscription, policy: policy);
  }

  /// 手动添加单个数据源（高级用户直接填 API 地址）。
  Future<SourceConfig> addCustomSource({
    required String name,
    required String api,
    SourceKind kind = SourceKind.maccms,
    int priority = 500,
  }) async {
    final config = SourceConfig(
      key: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim(),
      kind: kind,
      api: api.trim(),
      priority: priority,
      comment: '用户手动添加',
    );
    final errors = config.validate();
    if (errors.isNotEmpty) {
      throw SourceConfigException(errors.join('；'));
    }
    await _repository.upsertSources(<SourceConfig>[config]);
    return config;
  }

  // ── 校验 ────────────────────────────────────────────────

  /// 单源可用性校验。
  ///
  /// 采用「真实探针」策略：发起一次真实搜索请求并走完整解析链路，
  /// 而非简单的 HTTP HEAD——因为源站"能连通"不代表"接口还能用"
  /// （大量源站页面正常但采集接口已被关闭）。
  Future<SourceValidationResult> validate(SourceConfig config) async {
    // 步骤 1：静态配置校验（零网络成本）
    final configErrors = config.validate();
    if (configErrors.isNotEmpty) {
      return SourceValidationResult(
        sourceKey: config.key,
        health: SourceHealth.invalid,
        latencyMs: 0,
        message: configErrors.join('；'),
        checkedAt: DateTime.now(),
      );
    }

    if (!_registry.canHandle(config)) {
      return SourceValidationResult(
        sourceKey: config.key,
        health: SourceHealth.invalid,
        latencyMs: 0,
        message: '缺少类型「${config.kind.wire}」对应的解析器',
        checkedAt: DateTime.now(),
      );
    }

    // 步骤 2：真实探针请求
    final stopwatch = Stopwatch()..start();
    try {
      final result = await _validationGate.run(
        () => _aggregator.search(
          AppConstants.healthProbeKeyword,
          <SourceConfig>[config],
          enforceRelevance: false,
          timeout: config.timeout,
        ),
      );
      stopwatch.stop();

      final report = result.reports.firstOrNull;
      final latency = report?.elapsedMs ?? stopwatch.elapsedMilliseconds;

      if (report == null) {
        return SourceValidationResult(
          sourceKey: config.key,
          health: SourceHealth.degraded,
          latencyMs: latency,
          message: '未取得探针结果',
          checkedAt: DateTime.now(),
        );
      }

      if (!report.ok) {
        return SourceValidationResult(
          sourceKey: config.key,
          health: SourceHealth.unreachable,
          latencyMs: latency,
          message: report.errorMessage ?? '请求失败',
          checkedAt: DateTime.now(),
        );
      }

      if (report.keptCount < AppConstants.healthMinSample) {
        return SourceValidationResult(
          sourceKey: config.key,
          health: SourceHealth.degraded,
          latencyMs: latency,
          sampleCount: report.keptCount,
          message: '接口连通但探针无有效结果（可能字段映射失配或接口已变更）',
          checkedAt: DateTime.now(),
        );
      }

      final sampleTitle = await _peekSampleTitle(config);

      if (latency > _slowThresholdMs) {
        return SourceValidationResult(
          sourceKey: config.key,
          health: SourceHealth.degraded,
          latencyMs: latency,
          sampleCount: report.keptCount,
          sampleTitle: sampleTitle,
          message: '响应较慢（${latency}ms），建议降低优先级',
          checkedAt: DateTime.now(),
        );
      }

      return SourceValidationResult(
        sourceKey: config.key,
        health: SourceHealth.healthy,
        latencyMs: latency,
        sampleCount: report.keptCount,
        sampleTitle: sampleTitle,
        checkedAt: DateTime.now(),
      );
    } catch (error) {
      stopwatch.stop();
      final failure = FailureMapper.map(error, source: config);
      return SourceValidationResult(
        sourceKey: config.key,
        health: SourceHealth.unreachable,
        latencyMs: stopwatch.elapsedMilliseconds,
        message: failure.message,
        checkedAt: DateTime.now(),
      );
    }
  }

  /// 批量校验（受控并发，避免一次性打爆全部源站）。
  Future<Map<String, SourceValidationResult>> validateAll(
    List<SourceConfig> sources, {
    int concurrency = 5,
  }) async {
    final gate = Semaphore(concurrency.clamp(1, 20));
    final entries = await Future.wait(
      sources.map((config) async {
        final result = await gate.run(() => validate(config));
        return MapEntry(config.key, result);
      }),
    );
    return Map<String, SourceValidationResult>.fromEntries(entries);
  }

  /// 轻量连通性探测（HTTP HEAD）。
  ///
  /// 与 [validate] 的区别：不消耗源站业务接口配额，仅用于判断
  /// "域名是否可达"。适合在用户滚动源列表时做即时状态展示。
  Future<bool> pingHost(SourceConfig config, {Duration? timeout}) async {
    if (config.api.trim().isEmpty) return false;
    final status = await _http.ping(
      config.api,
      headers: config.headers,
      timeout: timeout ?? const Duration(seconds: 5),
    );
    // 部分源站禁用 HEAD，返回 405/403 亦说明域名可达。
    return status > 0;
  }

  /// 探测样本标题：用于人工确认"这个源返回的内容是否对版"。
  Future<String?> _peekSampleTitle(SourceConfig config) async {
    try {
      final result = await _aggregator.search(
        AppConstants.healthProbeKeyword,
        <SourceConfig>[config],
        enforceRelevance: false,
        timeout: config.timeout,
      );
      if (result.items.isEmpty) return null;
      return result.items.first.primary.title;
    } catch (_) {
      return null;
    }
  }

  // ── 变更 ────────────────────────────────────────────────

  Future<void> setEnabled(String key, bool enabled) async {
    try {
      final sources = await _repository.loadSources();
      final index = sources.indexWhere((s) => s.key == key);
      if (index < 0) {
        throw SourceConfigException('数据源不存在：$key');
      }
      sources[index] = sources[index].copyWith(enabled: enabled);
      await _repository.saveSources(sources);
    } catch (error) {
      throw FailureMapper.map(error);
    }
  }

  Future<void> setPriority(String key, int priority) async {
    try {
      final sources = await _repository.loadSources();
      final index = sources.indexWhere((s) => s.key == key);
      if (index < 0) {
        throw SourceConfigException('数据源不存在：$key');
      }
      sources[index] = sources[index].copyWith(priority: priority);
      await _repository.saveSources(sources);
    } catch (error) {
      throw FailureMapper.map(error);
    }
  }

  Future<void> remove(String key) async {
    try {
      await _repository.removeSource(key);
    } catch (error) {
      throw FailureMapper.map(error);
    }
  }

  /// 批量启用/禁用（"一键全部关闭"）
  Future<void> setAllEnabled(List<String> keys, bool enabled) async {
    try {
      final sources = await _repository.loadSources();
      final keySet = keys.toSet();
      final updated = <SourceConfig>[
        for (final s in sources)
          keySet.contains(s.key) ? s.copyWith(enabled: enabled) : s,
      ];
      await _repository.saveSources(updated);
    } catch (error) {
      throw FailureMapper.map(error);
    }
  }

  /// 清空全部数据源。
  Future<void> clearAll() async {
    try {
      await _repository.clear();
    } catch (error) {
      throw FailureMapper.map(error);
    }
  }

  // ── 热更新 ──────────────────────────────────────────────

  /// 检查全部订阅是否有更新，返回「订阅ID → 新旧版本」映射。
  Future<Map<String, (int oldVersion, int newVersion)>> checkUpdates() async {
    final subscriptions = await _repository.loadSubscriptions();
    final updates = <String, (int, int)>{};

    await Future.wait(
      subscriptions.map((sub) async {
        try {
          final remote = await _repository.fetchSubscription(sub.url, etag: sub.etag);
          if (remote.version > sub.version) {
            updates[sub.id] = (sub.version, remote.version);
          }
        } on NotModifiedException {
          // 304：无更新
        } catch (_) {
          // 单个订阅检查失败不影响其它订阅
        }
      }),
    );
    return updates;
  }

  /// 刷新指定订阅（强制拉取并合并）。
  Future<SourceImportReport> refreshSubscription(
    String subscriptionId, {
    MergePolicy policy = const MergePolicy(),
  }) async {
    final subscriptions = await _repository.loadSubscriptions();
    final sub = subscriptions.firstWhereOrNull((s) => s.id == subscriptionId);
    if (sub == null) {
      throw SourceConfigException('订阅不存在：$subscriptionId');
    }
    if (sub.url.isEmpty) {
      throw const SourceConfigException('该订阅没有可用的远程地址');
    }
    return importFromUrl(sub.url, policy: policy);
  }

  // ── 内部：合并与持久化 ──────────────────────────────────

  Future<SourceImportReport> _mergeAndPersist(
    SourceSubscription subscription, {
    required MergePolicy policy,
  }) async {
    // 1) 协议版本校验：订阅要求高于客户端能力时拒绝导入
    if (!_isProtocolCompatible(subscription.protocol)) {
      throw ProtocolVersionException(
        subscription.protocol,
        '${AppConstants.protocolVersion} / ${AppConstants.tvboxProtocolVersion}',
      );
    }

    List<SourceConfig> localSources;
    List<SourceSubscription> localSubscriptions;
    try {
      localSources = await _repository.loadSources();
      localSubscriptions = await _repository.loadSubscriptions();
    } catch (error) {
      throw FailureMapper.map(error);
    }

    final localByKey = <String, SourceConfig>{
      for (final s in localSources) s.key: s,
    };

    final toPersist = <SourceConfig>[];
    var added = 0;
    var updated = 0;
    var skipped = 0;
    var invalid = 0;

    for (final incoming in subscription.sources) {
      // 2) 逐源配置校验
      final errors = incoming.validate();
      if (errors.isNotEmpty) {
        invalid++;
        continue;
      }
      if (!_registry.canHandle(incoming)) {
        // 客户端无解析能力的类型（如 TVBox spider）→ 跳过而非导入脏数据
        skipped++;
        continue;
      }
      if (!policy.importDisabledSources && !incoming.enabled) {
        skipped++;
        continue;
      }

      final existing = localByKey[incoming.key];
      if (existing == null) {
        toPersist.add(incoming);
        added++;
        continue;
      }

      // 3) 合并：保留用户本地覆盖项（开关、优先级、请求头）
      if (policy.preserveUserOverrides) {
        toPersist.add(
          incoming.copyWith(
            enabled: existing.enabled,
            priority: existing.priority,
            headers: <String, String>{
              ...incoming.headers,
              ...existing.headers,
            },
          ),
        );
      } else {
        toPersist.add(incoming);
      }
      updated++;
    }

    // 4) 持久化数据源
    try {
      if (toPersist.isNotEmpty) {
        await _repository.upsertSources(toPersist);
      }
    } catch (error) {
      throw FailureMapper.map(error);
    }

    // 5) 更新订阅元信息（同 url 覆盖，保留本地 id）
    final newSubscription = subscription.copyWith(
      id: localSubscriptions
              .firstWhereOrNull((s) => s.url.isNotEmpty && s.url == subscription.url)
              ?.id ??
          subscription.id,
      lastCheckedAt: DateTime.now(),
    );
    final mergedSubscriptions = <SourceSubscription>[
      for (final s in localSubscriptions)
        if (s.id != newSubscription.id && s.url != newSubscription.url) s,
      newSubscription,
    ];
    try {
      await _repository.saveSubscriptions(mergedSubscriptions);
    } catch (error) {
      throw FailureMapper.map(error);
    }

    return SourceImportReport(
      subscriptionId: newSubscription.id,
      subscriptionName: newSubscription.name,
      totalSources: subscription.sources.length,
      added: added,
      updated: updated,
      skipped: skipped,
      invalid: invalid,
      protocolVersion: subscription.protocol,
      message: invalid > 0 ? '有 $invalid 个源因配置非法被跳过' : null,
    );
  }

  bool _isProtocolCompatible(String protocol) {
    final value = protocol.trim().toLowerCase();
    if (value.isEmpty) return true;
    // 本协议：主版本号一致即兼容（v1.x 均可）
    if (value.startsWith('moviehub/')) {
      final major = value.split('/').last.split('.').first;
      final supportedMajor =
          AppConstants.protocolVersion.split('/').last.split('.').first;
      return major == supportedMajor;
    }
    // TVBox 生态共用导入通道
    if (value.startsWith('tvbox/')) return true;
    return false;
  }
}
