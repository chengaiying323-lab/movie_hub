/// 影片标题归一化工具——多源去重聚合的核心依赖。
///
/// 同一部影片在不同源站的标题形态差异极大：
/// ```text
/// 沙丘2 / 沙丘 2 / 沙丘Ⅱ / 沙丘：第二部(2024) / 【高清】沙丘 2 1080P 国语
/// ```
/// 朴素的 `title == title` 去重基本失效，必须做结构化归一。
class TitleNormalizer {
  const TitleNormalizer._();

  /// 需要在归一化阶段剔除的噪声字符（标点、空白、装饰符）。
  static final RegExp _punctuation = RegExp(
    r'[\s\-_~·．.．。，,、!！?？:：;；/\\|()（）\[\]【】<>《》"“”'
    "'"
    r'’‘*#+&]',
  );

  /// 季/部标记：`第二季`、`第3部`
  static final RegExp _seasonMarker =
      RegExp(r'第\s*[0-9一二三四五六七八九十]+\s*[季部]');

  /// 尾部集数标记：`全24集`、`更新至12集`、`共36话`
  static final RegExp _episodeMarker =
      RegExp(r'(更新至|全|共)?\s*\d+\s*[集话期]');

  /// 画质 / 语言 / 版本等后缀噪声。
  static final RegExp _qualityMarker = RegExp(
    r'(4k|8k|1080p|720p|2160p|hd|bd|蓝光|超清|高清|国语|粤语|中字|双语|'
    r'未删减|完整版|加长版|剧场版|预告|ts|tc|hdts|web-?dl|hdtv|remux)',
    caseSensitive: false,
  );

  static final RegExp _yearMarker = RegExp(r'(19|20)\d{2}');

  /// 罗马数字 ↔ 阿拉伯数字（用于 `沙丘Ⅱ` → `沙丘2`）。
  static const Map<String, String> _romanMap = <String, String>{
    'Ⅰ': '1', 'Ⅱ': '2', 'Ⅲ': '3', 'Ⅳ': '4', 'Ⅴ': '5',
    'Ⅵ': '6', 'Ⅶ': '7', 'Ⅷ': '8', 'Ⅸ': '9', 'Ⅹ': '10',
  };

  /// 归一化：用于生成去重键。返回**小写、无标点、无噪声后缀**的紧凑串。
  static String normalize(String input) {
    if (input.trim().isEmpty) return '';

    var text = _toHalfWidth(input).toLowerCase();

   // 罗马数字 → 阿拉伯数字
    _romanMap.forEach((k, v) => text = text.replaceAll(k, v));

    // 去除年份
    text = text.replaceAll(_yearMarker, '');

    // 去除画质/语言/版本噪声、季部标记、集数标记
    text = text
        .replaceAll(_qualityMarker, '')
        .replaceAll(_seasonMarker, '')
        .replaceAll(_episodeMarker, '');

    // 去除标点与空白
    text = text.replaceAll(_punctuation, '');

    return text.trim();
  }

  /// 从标题中抽取年份（用于辅助去重判定），无则返回 null。
  static int? extractYear(String input) {
    final match = _yearMarker.firstMatch(_toHalfWidth(input));
    if (match == null) return null;
    return int.tryParse(match.group(0)!);
  }

  /// 相关性判定：归一化后互相包含即认为相关。
  ///
  /// 苹果CMS 搜索接口的模糊匹配常返回大量无关结果（例如搜"三体"返回
  /// "三体前传：球状闪电"），聚合层必须做一次相关性过滤。
  static bool isRelevant(String keyword, String title) {
    final k = normalize(keyword);
    final t = normalize(title);
    if (k.isEmpty || t.isEmpty) return false;
    return t.contains(k) || k.contains(t);
  }

  /// 全角 → 半角转换，同时处理全角空格。
  static String _toHalfWidth(String input) {
    const int fullWidthStart = 0xFF01;
    const int fullWidthEnd = 0xFF5E;
    const int offset = 0xFEE0;

    final buffer = StringBuffer();
    for (final rune in input.runes) {
      if (rune >= fullWidthStart && rune <= fullWidthEnd) {
        buffer.writeCharCode(rune - offset);
      } else if (rune == 0x3000) {
        buffer.write(' ');
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }
}
