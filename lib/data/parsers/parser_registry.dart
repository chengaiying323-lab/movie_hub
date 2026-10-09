import '../../core/error/exceptions.dart';
import '../../domain/entities/source_config.dart';
import 'maccms_parser.dart';
import 'source_parser.dart';
import 'tvbox_json_parser.dart';

/// 解析器注册表。
///
/// 职责：根据 [SourceConfig.kind] 选出对应的 [SourceParser]。
/// 新增协议形态时只需 `register()` 一个新解析器，**无需修改调用方**。
///
/// 线程/隔离说明：注册表在应用启动时构建一次，之后只读，
/// 因此可安全地被多个并发搜索任务共享。
class ParserRegistry {
  ParserRegistry({List<SourceParser>? parsers})
      : _parsers = List<SourceParser>.unmodifiable(
          parsers ??
              const <SourceParser>[
                MaccmsParser(),
                TvboxJsonParser(),
              ],
        ) {
    _rebuildIndex();
  }

  List<SourceParser> _parsers;
  final Map<SourceKind, SourceParser> _index = <SourceKind, SourceParser>{};

  void _rebuildIndex() {
    _index.clear();
    for (final parser in _parsers) {
      _index[parser.kind] = parser;
    }
  }

  /// 运行时扩展（插件化接入新协议）。
  void register(SourceParser parser) {
    _parsers = List<SourceParser>.unmodifiable(<SourceParser>[..._parsers, parser]);
    _rebuildIndex();
  }

  List<SourceParser> get parsers => _parsers;

  /// 该配置是否具备可用的解析器。
  bool canHandle(SourceConfig config) => _index.containsKey(config.kind);

  /// 取解析器；不支持时抛出 [SourceParseException]，由上层转为 Failure。
  SourceParser resolve(SourceConfig config) {
    final parser = _index[config.kind];
    if (parser == null) {
      throw SourceParseException(
        '暂不支持的数据源类型「${config.kind.wire}」'
        '（该类型需要外置解析运行时，客户端无法直接解析）',
        sourceKey: config.key,
      );
    }
    return parser;
  }
}
