import 'package:meta/meta.dart';

/// 剧集（选集）实体。
///
/// 对应苹果CMS播放串中的最小单元：`第1集$https://.../index.m3u8`
@immutable
class Episode {
  const Episode({
    required this.index,
    required this.name,
    required this.url,
    this.flag,
  });

  /// 在所属线路内的顺序号（从 0 开始）。
  final int index;

  /// 展示名，如「第01集」「正片」「预告」。
  final String name;

  /// 播放地址。可能是直链（m3u8/mp4）、磁力链，或需要解析的页面地址。
  final String url;

  /// 附加标记：`vip`、`paid`、`preview` 等，用于 UI 灰显。
  final String? flag;

  /// 可直接投喂给播放器的地址（排除 `#` 占位与脚本注入串）。
  bool get isPlayable {
    final u = url.trim();
    if (u.isEmpty || u == '#' || u == 'javascript:void(0)') return false;
    if (u.startsWith('<')) return false; // 部分源站返回 `<script>` 占位
    return true;
  }

  /// 是否为直链媒体（无需二次解析）。
  bool get isDirectMedia {
    final u = url.trim().toLowerCase();
    return u.startsWith('http') &&
        (u.contains('.m3u8') ||
            u.contains('.mp4') ||
            u.contains('.flv') ||
            u.contains('.mkv') ||
            u.contains('.ts'));
  }

  /// 是否为磁力/ed2k 资源（需走下载器或 P2P 播放）。
  bool get isMagnet {
    final u = url.trim().toLowerCase();
    return u.startsWith('magnet:') || u.startsWith('ed2k:');
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'index': index,
        'name': name,
        'url': url,
        if (flag != null) 'flag': flag,
      };

  factory Episode.fromJson(Map<String, dynamic> json) => Episode(
        index: (json['index'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        url: json['url'] as String? ?? '',
        flag: json['flag'] as String?,
      );

  Episode copyWith({int? index, String? name, String? url, String? flag}) =>
      Episode(
        index: index ?? this.index,
        name: name ?? this.name,
        url: url ?? this.url,
        flag: flag ?? this.flag,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Episode &&
          other.index == index &&
          other.name == name &&
          other.url == url;

  @override
  int get hashCode => Object.hash(index, name, url);

  @override
  String toString() => 'Episode($index, $name, ${url.length > 48 ? '${url.substring(0, 48)}…' : url})';
}
