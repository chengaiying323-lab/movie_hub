import '../../domain/entities/movie.dart';
import '../../domain/entities/source_config.dart';

/// 数据源解析器抽象。
///
/// 架构定位
/// ------------------------------------------------------------------
/// 解析层是「**声明式协议** → **领域模型**」的唯一翻译器。
///
/// - 它**不认识任何具体站点**，只认识 `FieldMapping` / `EndpointTemplate`
///   这类协议描述；
/// - 它**不做网络请求**（职责单一，便于单元测试——喂入固定 JSON 即可验证）；
/// - 它**不抛领域外的异常**，所有异常统一收敛为 [SourceParseException]，
///   由上层 service 转为 [Failure]。
///
/// 新增一种源站形态 = 新增一个 [SourceParser] 实现 + 注册到 `ParserRegistry`，
/// **不需要修改任何已有代码**（开闭原则）。
abstract class SourceParser {
  const SourceParser();

  /// 本解析器负责的数据源类型。
  SourceKind get kind;

  /// 是否可处理该配置。
  bool supports(SourceConfig config) => config.kind == kind;

  /// 解析「列表型」响应（搜索 / 分类浏览）。
  ///
  /// 列表接口通常不返回播放地址，因此 [withPlaylist] 默认为 false，
  /// 以减少无谓的字符串拆解开销（单次聚合可能要解析上千条）。
  List<Movie> parseList(
    Object? payload,
    SourceConfig config, {
    bool withPlaylist = false,
  });

  /// 解析「详情型」响应，必须返回带 [Movie.sources] 的完整模型。
  ///
  /// [fallbackId] 用于详情接口未回传 id 时兜底（部分源站如此）。
  Movie? parseDetail(
    Object? payload,
    SourceConfig config, {
    String? fallbackId,
  });

  /// 探针解析：仅判断「这份响应里是否有可用影视条目」，
  /// 用于数据源可用性校验，避免完整解析的成本。
  bool canExtractAny(Object? payload, SourceConfig config) =>
      parseList(payload, config).isNotEmpty;
}
