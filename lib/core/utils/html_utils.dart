/// HTML 清洗与 URL 归一化工具。
///
/// 影视源站返回的简介字段普遍夹杂 HTML（`<p>`, `<br>`, 富文本样式），
/// 封面图则大量使用协议相对地址（`//img.xx.com/a.jpg`）或站点相对路径。
/// 若不在解析层统一处理，这些脏数据会直接渗透到 UI 层。
class HtmlUtils {
  const HtmlUtils._();

  static final RegExp _tagPattern = RegExp(r'<[^>]*>');
  static final RegExp _brPattern = RegExp(r'<br\s*/?>', caseSensitive: false);
  static final RegExp _blockEndPattern =
      RegExp(r'</(p|div|li|h[1-6])\s*>', caseSensitive: false);
  static final RegExp _multiSpace = RegExp(r'[ \t\u00A0]+');
  static final RegExp _multiNewline = RegExp(r'\n{3,}');

  static const Map<String, String> _entities = <String, String>{
    '&nbsp;': ' ',
    '&amp;': '&',
    '&lt;': '<',
    '&gt;': '>',
    '&quot;': '"',
    '&#39;': "'",
    '&apos;': "'",
    '&ldquo;': '“',
    '&rdquo;': '”',
    '&hellip;': '…',
    '&mdash;': '—',
  };

  /// 剥离 HTML 标签并还原常见实体，输出纯文本。
  static String stripHtml(String? input) {
    if (input == null || input.isEmpty) return '';
    var text = input
        .replaceAll(_brPattern, '\n')
        .replaceAll(_blockEndPattern, '\n')
        .replaceAll(_tagPattern, '');
    _entities.forEach((entity, replacement) {
      text = text.replaceAll(entity, replacement);
    });
    // 数字实体 &#123;
    text = text.replaceAllMapped(
      RegExp(r'&#(\d+);'),
      (m) => String.fromCharCode(int.tryParse(m.group(1)!) ?? 32),
    );
    text = text
        .replaceAll(_multiSpace, ' ')
        .replaceAll(_multiNewline, '\n\n');
    return text.trim();
  }

  /// 将源站返回的地址补全为绝对 URL。
  ///
  /// - `//img.xx.com/a.jpg` → `https://img.xx.com/a.jpg`（继承 api 协议）
  /// - `/upload/a.jpg`      → `https://api.xx.com/upload/a.jpg`
  /// - `https://...`        → 原样返回
  /// - 空串 / `javascript:` → 返回 null
  static String? resolveUrl(String? raw, String api) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return null;
    if (value.startsWith('javascript:') || value.startsWith('data:image')) {
      return null;
    }
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    final base = Uri.tryParse(api);
    if (value.startsWith('//')) {
      final scheme = base?.scheme ?? 'https';
      return '$scheme:$value';
    }
    if (base == null) return value;
    try {
      return base.resolve(value).toString();
    } catch (_) {
      return value;
    }
  }

  /// 判定字符串是否为「空值语义」（源站常用 `''`/`null`/`0`/`无` 占位）。
  static bool isBlank(String? value) {
    if (value == null) return true;
    final v = value.trim().toLowerCase();
    return v.isEmpty || v == 'null' || v == '0' || v == '无' || v == '暂无' || v == 'n/a';
  }
}
