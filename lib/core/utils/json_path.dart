/// 轻量 JSON 路径取值器。
///
/// 为什么不用 json_serializable / freezed 硬编码字段？
/// ------------------------------------------------------------------
/// 影视数据源的字段名在苹果CMS、TVBox、自建 JSON API 之间高度不一致
/// （`vod_name` / `name` / `title` / `vodName`）。若把字段名写死在 Model 的
/// `fromJson` 中，每适配一个新源就要改一次代码——这正是"爬虫逻辑硬编码在
/// 客户端"的典型反模式。
///
/// 因此本客户端把「字段映射」抽象为**声明式配置**（见 `FieldMapping`），
/// 由本工具类在运行时按路径取值。新增数据源只需改 JSON 配置，无需发版。
///
/// 支持的语法：
/// - 点分路径：`vod_name`、`data.list`、`vod.title`
/// - 数组下标：`list[0].vod_name` 或 `list.0.vod_name`
/// - 多路径回退：`vod_name||name||title`（取第一个非空值）
/// - 根节点：`$`
library;

class JsonPath {
  const JsonPath._();

  static final RegExp _segmentPattern = RegExp(r'^([^\[\]]*)((?:\[\d+\])*)$');
  static final RegExp _indexPattern = RegExp(r'\[(\d+)\]');

  /// 读取首个非空匹配值，支持 `||` 回退。
  static Object? read(Object? root, String? path) {
    if (root == null || path == null || path.trim().isEmpty) return null;
    for (final candidate in path.split('||')) {
      final value = readSingle(root, candidate.trim());
      if (value != null && value.toString().trim().isNotEmpty) return value;
    }
    return null;
  }

  /// 严格读取单条路径。
  static Object? readSingle(Object? root, String path) {
    if (path.isEmpty) return null;
    if (path == r'$') return root;
    var normalized = path;
    if (normalized.startsWith(r'$.')) {
      normalized = normalized.substring(2);
    }

    Object? cursor = root;
    for (final segment in normalized.split('.')) {
      if (cursor == null) return null;
      if (segment.isEmpty) continue;

      final match = _segmentPattern.firstMatch(segment);
      if (match == null) return null;

      final fieldName = match.group(1)!;
      if (fieldName.isNotEmpty) {
        cursor = _descend(cursor, fieldName);
      }

      final indexPart = match.group(2) ?? '';
      if (indexPart.isNotEmpty) {
        for (final m in _indexPattern.allMatches(indexPart)) {
          if (cursor is! List) return null;
          final index = int.parse(m.group(1)!);
          if (index < 0 || index >= cursor.length) return null;
          cursor = cursor[index];
        }
      }
    }
    return cursor;
  }

  static Object? _descend(Object? node, String key) {
    if (node is Map) return node[key];
    if (node is List) {
      final index = int.tryParse(key);
      if (index != null) {
        return (index >= 0 && index < node.length) ? node[index] : null;
      }
      // 隐式展开：对列表内每个元素取同名字段（常见于 `list.vod_name` 简化写法）
      final mapped = <Object?>[];
      for (final element in node) {
        final value = _descend(element, key);
        if (value != null) mapped.add(value);
      }
      return mapped.isEmpty ? null : mapped;
    }
    return null;
  }

  // ── 类型化读取 ──────────────────────────────────────────

  static String str(Object? root, String? path, {String fallback = ''}) {
    final value = read(root, path);
    if (value == null) return fallback;
    return value is String ? value : value.toString();
  }

  static String? strOrNull(Object? root, String? path) {
    final value = read(root, path);
    if (value == null) return null;
    final text = value is String ? value : value.toString();
    final trimmed = text.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static int? intOrNull(Object? root, String? path) {
    final value = read(root, path);
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim());
  }

  static double? doubleOrNull(Object? root, String? path) {
    final value = read(root, path);
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().trim());
  }

  static bool boolOrNull(Object? root, String? path) {
    final value = read(root, path);
    if (value == null) return null;
    if (value is bool) return value;
    final text = value.toString().trim().toLowerCase();
    if (text == '1' || text == 'true' || text == 'yes') return true;
    if (text == '0' || text == 'false' || text == 'no') return false;
    return null;
  }

  /// 将路径结果归一化为 `List<Map<String, Object?>>`，自动处理
  /// `{list: [...]}` / `{data: {list: [...]}}` / 直接数组 三种形态。
  static List<Map<String, Object?>> mapList(Object? root, String? path) {
    final value = read(root, path);
    if (value is List) {
      return value.whereType<Map>().map(_castMap).toList(growable: false);
    }
    if (value is Map) return <Map<String, Object?>>[_castMap(value)];
    return const <Map<String, Object?>>[];
  }

  /// 把字符串按分隔符切成去空去重后的列表。
  static List<String> splitList(
    String? raw, {
    String separator = ',',
    bool dedupe = true,
  }) {
    if (raw == null || raw.trim().isEmpty) return const <String>[];
    final parts = raw
        .split(separator)
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (!dedupe) return parts;
    final seen = <String>{};
    final result = <String>[];
    for (final part in parts) {
      if (seen.add(part)) result.add(part);
    }
    return result;
  }

  static Map<String, Object?> _castMap(Map<dynamic, dynamic> source) {
    return source.map((k, v) => MapEntry(k.toString(), v as Object?));
  }
}
