import '../../core/utils/json_path.dart';
import '../../domain/entities/source_config.dart';
import 'json_source_parser.dart';

/// 苹果CMS v10 采集接口解析器。
///
/// 标准响应结构
/// ------------------------------------------------------------------
/// ```json
/// {
///   "code": 1,
///   "msg": "数据列表",
///   "page": 1,
///   "pagecount": 100,
///   "limit": "20",
///   "total": 2000,
///   "list": [
///     {
///       "vod_id": 12345,
///       "vod_name": "沙丘2",
///       "vod_pic": "https://.../a.jpg",
///       "type_id": 6,
///       "type_name": "动作片",
///       "vod_year": "2024",
///       "vod_area": "美国",
///       "vod_remarks": "HD高清",
///       "vod_actor": "提莫西·查拉梅,赞达亚",
///       "vod_director": "丹尼斯·维伦纽瓦",
///       "vod_content": "<p>剧情简介...</p>",
///       "vod_play_from": "量子线路$$$闪电线路",
///       "vod_play_url": "第1集$https://a.m3u8#第2集$https://b.m3u8$$$正片$https://c.m3u8"
///     }
///   ]
/// }
/// ```
///
/// 需要注意的源站差异（均已在协议中留有开关，无需改代码）：
/// - `code` 字段部分站点返回字符串 `"1"`；
/// - 部分站点把 `list` 包在 `data` 下；
/// - 分类列表接口用 `class` 数组而非 `list`。
class MaccmsParser extends JsonSourceParser {
  const MaccmsParser();

  @override
  SourceKind get kind => SourceKind.maccms;

  @override
  List<Map<String, Object?>> extractItems(Object? payload, SourceConfig config) {
    // 1) 优先按协议声明的路径取值
    final declared = JsonPath.mapList(payload, config.fields.list);
    if (declared.isNotEmpty) return declared;

    // 2) 常见兜底：data.list / data / result.list
    for (final path in const <String>[
      'data.list',
      'data',
      'result.list',
      'result',
      'items',
      'videos',
    ]) {
      final fallback = JsonPath.mapList(payload, path);
      if (fallback.isNotEmpty) return fallback;
    }

    // 3) 根节点本身就是数组
    if (payload is List) {
      return payload
          .whereType<Map>()
          .map((e) => e.cast<String, Object?>())
          .toList(growable: false);
    }

    return const <Map<String, Object?>>[];
  }

  /// 判定响应是否为「苹果CMS 语义的成功」。
  ///
  /// 部分站点在无结果时返回 `{"code":0,"msg":"没有找到数据"}`，
  /// 这与「接口挂了」是两回事，校验时须区分，否则会误判源不可用。
  static bool isBusinessSuccess(Object? payload) {
    if (payload is! Map) return false;
    final code = payload['code'];
    if (code == null) return true;
    final normalized = code.toString().trim();
    return normalized == '1' || normalized == '200' || normalized == 'true';
  }

  /// 提取源站返回的业务提示信息（用于错误上报）。
  static String? extractMessage(Object? payload) {
    if (payload is! Map) return null;
    final msg = payload['msg'] ?? payload['message'] ?? payload['info'];
    if (msg == null) return null;
    final text = msg.toString().trim();
    return text.isEmpty ? null : text;
  }
}
