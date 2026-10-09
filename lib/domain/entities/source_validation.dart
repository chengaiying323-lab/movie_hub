import 'package:meta/meta.dart';

/// 数据源健康度。
enum SourceHealth {
  /// 尚未校验。
  unknown('未校验'),

  /// 完全可用：请求成功、JSON 可解析、字段映射命中、有有效样本。
  healthy('可用'),

  /// 降级：可连通但样本不足、字段命中率低或响应过慢。
  degraded('降级'),

  /// 不可达：超时 / 连接失败 / 非 2xx。
  unreachable('不可达'),

  /// 配置非法或协议不受支持（无需发起网络请求）。
  invalid('配置无效');

  const SourceHealth(this.label);
  final String label;

  bool get isUsable => this == SourceHealth.healthy || this == SourceHealth.degraded;
  bool get isError => this == SourceHealth.unreachable || this == SourceHealth.invalid;
}

/// 数据源校验结果。
@immutable
class SourceValidationResult {
  const SourceValidationResult({
    required this.sourceKey,
    required this.health,
    required this.latencyMs,
    this.sampleCount = 0,
    this.sampleTitle,
    this.message,
    this.statusCode,
    this.checkedAt,
  });

  final String sourceKey;
  final SourceHealth health;
  final int latencyMs;

  /// 探针返回的有效条目数。
  final int sampleCount;

  /// 探针返回的首条标题（人工确认源站内容是否正确）。
  final String? sampleTitle;

  /// 失败原因 / 降级原因。
  final String? message;

  final int? statusCode;
  final DateTime? checkedAt;

  bool get ok => health.isUsable;

  /// 评分：用于「自动挑选最快可用源」。
  /// 健康源按延迟排序；非健康源排到最后。
  double get score {
    switch (health) {
      case SourceHealth.healthy:
        return 1.0;
      case SourceHealth.degraded:
        return 0.5;
      case SourceHealth.unknown:
        return 0.3;
      case SourceHealth.unreachable:
      case SourceHealth.invalid:
        return 0.0;
    }
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'source_key': sourceKey,
        'health': health.name,
        'latency_ms': latencyMs,
        'sample_count': sampleCount,
        'sample_title': sampleTitle,
        'message': message,
        'status_code': statusCode,
        'checked_at': checkedAt?.toIso8601String(),
      };

  factory SourceValidationResult.fromJson(Map<String, dynamic> json) =>
      SourceValidationResult(
        sourceKey: json['source_key'] as String? ?? '',
        health: SourceHealth.values.firstWhere(
          (e) => e.name == json['health'],
          orElse: () => SourceHealth.unknown,
        ),
        latencyMs: (json['latency_ms'] as num?)?.toInt() ?? 0,
        sampleCount: (json['sample_count'] as num?)?.toInt() ?? 0,
        sampleTitle: json['sample_title'] as String?,
        message: json['message'] as String?,
        statusCode: (json['status_code'] as num?)?.toInt(),
        checkedAt: DateTime.tryParse(json['checked_at'] as String? ?? ''),
      );

  @override
  String toString() =>
      'SourceValidationResult($sourceKey, ${health.label}, ${latencyMs}ms, samples=$sampleCount)';
}

/// 订阅导入报告。
@immutable
class SourceImportReport {
  const SourceImportReport({
    required this.subscriptionId,
    required this.subscriptionName,
    required this.totalSources,
    required this.added,
    required this.updated,
    required this.skipped,
    required this.invalid,
    this.protocolVersion = '',
    this.message,
  });

  final String subscriptionId;
  final String subscriptionName;
  final int totalSources;
  final int added;
  final int updated;

  /// 因类型不受支持或已存在且无变更而跳过。
  final int skipped;

  /// 配置非法的数量。
  final int invalid;

  final String protocolVersion;
  final String? message;

  String get summary =>
      '共 $totalSources 个源：新增 $added、更新 $updated、跳过 $skipped、无效 $invalid';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'subscription_id': subscriptionId,
        'subscription_name': subscriptionName,
        'total_sources': totalSources,
        'added': added,
        'updated': updated,
        'skipped': skipped,
        'invalid': invalid,
        'protocol_version': protocolVersion,
        'message': message,
      };
}
