import 'package:meta/meta.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/json_path.dart';

/// 数据源类型。
///
/// 客户端只内置**声明式协议**的解析器，不内置任何站点特化代码。
enum SourceKind {
  /// 苹果CMS v10 标准采集接口（`api.php/provide/vod/`）。
  maccms('maccms'),

  /// 通用 JSON API（TVBox type=0/1 站点、自建接口）。
  tvboxJson('tvbox_json'),

  /// TVBox spider 型源（type=3/4，依赖 jar/JS 运行时）。
  /// 客户端无 JS/Java 运行时，标记为「需服务端中转」，导入时可选择禁用。
  tvboxSpider('tvbox_spider'),

  /// 完全自定义（依赖 `field_map` + `endpoints` 描述全部行为）。
  custom('custom');

  const SourceKind(this.wire);

  /// 协议中的字符串标识。
  final String wire;

  static SourceKind fromWire(String? value) {
    if (value == null) return SourceKind.custom;
    final normalized = value.trim().toLowerCase();
    for (final kind in SourceKind.values) {
      if (kind.wire == normalized) return kind;
    }
    return SourceKind.custom;
  }

  /// 客户端是否具备原生解析能力。
  bool get isClientSupported => this != SourceKind.tvboxSpider;
}

/// 端点模板（Endpoint Template）。
///
/// 用字符串模板而非硬编码 URL 拼接，使同一套解析器可服务任意站点。
///
/// 可用占位符：
/// - `{api}`  数据源根地址
/// - `{wd}`   搜索关键词（已 URL 编码）
/// - `{pg}`   页码
/// - `{id}`   资源 ID（详情）
/// - `{tid}`  分类 ID（分类列表）
/// - `{ext}`  源的扩展参数
@immutable
class EndpointTemplate {
  const EndpointTemplate({
    required this.search,
    required this.detail,
    this.category,
    this.variables = const <String, String>{},
  });

  final String search;
  final String detail;
  final String? category;

  /// 附加的固定查询参数（部分源站需要 `?ac=list&token=xxx`）。
  final Map<String, String> variables;

  /// 各内置类型的默认端点模板。
  factory EndpointTemplate.defaultsFor(SourceKind kind) {
    switch (kind) {
      case SourceKind.maccms:
        return const EndpointTemplate(
          search: '{api}?ac=videolist&wd={wd}&pg={pg}',
          detail: '{api}?ac=videolist&ids={id}',
          category: '{api}?ac=videolist&t={tid}&pg={pg}',
        );
      case SourceKind.tvboxJson:
        return const EndpointTemplate(
          search: '{api}?wd={wd}&ac=videolist&pg={pg}',
          detail: '{api}?ac=videolist&ids={id}',
          category: '{api}?ac=videolist&t={tid}&pg={pg}',
        );
      case SourceKind.tvboxSpider:
      case SourceKind.custom:
        return const EndpointTemplate(search: '', detail: '');
    }
  }

  /// 渲染模板。
  ///
  /// [args] 中的值会**先做 URL 编码再替换**，避免中文关键词破坏查询串。
  /// 若模板为空则返回 null，调用方据此判定「该源不支持此操作」。
  String? render(String? template, Map<String, String> args) {
    if (template == null || template.trim().isEmpty) return null;

    final merged = <String, String>{...variables, ...args};
    var output = template;
    merged.forEach((key, value) {
      output = output.replaceAll('{$key}', value);
    });

    // 未替换的占位符说明配置有误，直接失败优于发出错误请求。
    final leftovers = RegExp(r'\{(\w+)\}').allMatches(output);
    if (leftovers.isNotEmpty) {
      final missing = leftovers.map((m) => m.group(0)).toSet().join(', ');
      throw ArgumentError('端点模板存在未定义占位符: $missing（模板: $template）');
    }
    return output;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'search': search,
        'detail': detail,
        if (category != null) 'category': category,
        if (variables.isNotEmpty) 'variables': variables,
      };

  factory EndpointTemplate.fromJson(Map<String, dynamic>? json, SourceKind kind) {
    if (json == null || json.isEmpty) return EndpointTemplate.defaultsFor(kind);
    final defaults = EndpointTemplate.defaultsFor(kind);
    return EndpointTemplate(
      search: json['search'] as String? ?? defaults.search,
      detail: json['detail'] as String? ?? defaults.detail,
      category: json['category'] as String? ?? defaults.category,
      variables: (json['variables'] as Map<dynamic, dynamic>? ?? const {})
          .map((k, v) => MapEntry(k.toString(), v.toString())),
    );
  }
}

/// 字段映射表（Field Mapping）。
///
/// 每一项都是「一条或多条 JSON 路径」，用 `||` 分隔构成回退链。
/// 新增数据源 = 新增一份 JSON 映射，**不需要改 Dart 代码**。
@immutable
class FieldMapping {
  const FieldMapping({
    this.list = 'list||data.list||data||result.list',
    this.id = 'vod_id||id||vid||vodId',
    this.name = 'vod_name||name||title||vodName',
    this.subTitle = 'vod_sub||sub_title||subName',
    this.poster = 'vod_pic||pic||poster||cover||vod_pic_thumb',
    this.backdrop = 'vod_pic_slide||vod_pic_bg||backdrop||picture',
    this.typeId = 'type_id||typeId||tid',
    this.typeName = 'type_name||typeName||class||category',
    this.categories = 'vod_class||class_name||vod_class_name',
    this.year = 'vod_year||year||vodYear',
    this.area = 'vod_area||area||vodArea',
    this.language = 'vod_lang||language||lang',
    this.remarks = 'vod_remarks||remarks||note||vod_note',
    this.actors = 'vod_actor||actor||actors||vodActor',
    this.directors = 'vod_director||director||directors||vodDirector',
    this.description = 'vod_content||vod_blurb||content||desc||description',
    this.score = 'vod_score||score||rating||vod_douban_score',
    this.duration = 'vod_duration||duration||runtime',
    this.updatedAt = 'vod_time||updated_at||last||time',
    this.playFrom = 'vod_play_from||play_from||from||playFrom',
    this.playUrl = 'vod_play_url||play_url||url||playUrl',
    this.detailUrl = 'vod_url||detail_url||link',
  });

  final String list;
  final String id;
  final String name;
  final String subTitle;
  final String poster;
  final String backdrop;
  final String typeId;
  final String typeName;
  final String categories;
  final String year;
  final String area;
  final String language;
  final String remarks;
  final String actors;
  final String directors;
  final String description;
  final String score;
  final String duration;
  final String updatedAt;
  final String playFrom;
  final String playUrl;
  final String detailUrl;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'list': list,
        'id': id,
        'name': name,
        'sub_title': subTitle,
        'poster': poster,
        'backdrop': backdrop,
        'type_id': typeId,
        'type_name': typeName,
        'categories': categories,
        'year': year,
        'area': area,
        'language': language,
        'remarks': remarks,
        'actors': actors,
        'directors': directors,
        'description': description,
        'score': score,
        'duration': duration,
        'updated_at': updatedAt,
        'play_from': playFrom,
        'play_url': playUrl,
        'detail_url': detailUrl,
      };

  factory FieldMapping.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return const FieldMapping();
    const base = FieldMapping();
    String pick(String key, String fallback) {
      final value = json[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
      return fallback;
    }

    return FieldMapping(
      list: pick('list', base.list),
      id: pick('id', base.id),
      name: pick('name', base.name),
      subTitle: pick('sub_title', base.subTitle),
      poster: pick('poster', base.poster),
      backdrop: pick('backdrop', base.backdrop),
      typeId: pick('type_id', base.typeId),
      typeName: pick('type_name', base.typeName),
      categories: pick('categories', base.categories),
      year: pick('year', base.year),
      area: pick('area', base.area),
      language: pick('language', base.language),
      remarks: pick('remarks', base.remarks),
      actors: pick('actors', base.actors),
      directors: pick('directors', base.directors),
      description: pick('description', base.description),
      score: pick('score', base.score),
      duration: pick('duration', base.duration),
      updatedAt: pick('updated_at', base.updatedAt),
      playFrom: pick('play_from', base.playFrom),
      playUrl: pick('play_url', base.playUrl),
      detailUrl: pick('detail_url', base.detailUrl),
    );
  }
}

/// 播放串拆解规则。
///
/// 苹果CMS 原始的播放数据结构是一段「双层分隔的形状串」：
/// ```text
/// vod_play_from = "线路1$$$线路2"
/// vod_play_url  = "第1集$url1#第2集$url2$$$第01话$urlA#第02话$urlB"
/// ```
/// 各源站使用的分隔符并不统一（有的用 `$$$`，有的用 `$$$$`，剧集有用 `#` 有用 `&`），
/// 因此分隔符必须可由协议声明。
@immutable
class PlaylistRule {
  const PlaylistRule({
    this.sourceSeparator = AppConstants.defaultSourceSeparator,
    this.episodeSeparator = AppConstants.defaultEpisodeSeparator,
    this.nameSeparator = AppConstants.defaultEpisodeNameSeparator,
    this.reverseEpisodes = false,
    this.flagNames = const <String, String>{},
  });

  /// 线路之间的分隔符。
  final String sourceSeparator;

  /// 剧集之间的分隔符。
  final String episodeSeparator;

  /// 剧集名与地址之间的分隔符。
  final String nameSeparator;

  /// 是否倒序排列剧集（部分源站新集在前）。
  final bool reverseEpisodes;

  /// 线路标志 → 展示名映射，如 `{"dytt": "电影天堂线路"}`。
  final Map<String, String> flagNames;

  /// 按 [flag] 取展示名；未配置时回退为 flag 本身。
  String displayNameOf(String flag) {
    final mapped = flagNames[flag];
    if (mapped != null && mapped.trim().isNotEmpty) return mapped;
    return _humanize(flag);
  }

  static String _humanize(String flag) {
    switch (flag.toLowerCase()) {
      case 'm3u8':
        return 'M3U8 线路';
      case 'lzm3u8':
        return '量子线路';
      case 'wjm3u8':
        return '无尽线路';
      case 'sdm3u8':
        return '闪电线路';
      case 'ffm3u8':
        return '非凡线路';
      case 'bjm3u8':
        return '暴风线路';
      case 'tkm3u8':
        return '天空线路';
      default:
        return flag.isEmpty ? '默认线路' : flag;
    }
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'source_separator': sourceSeparator,
        'episode_separator': episodeSeparator,
        'name_separator': nameSeparator,
        'reverse_episodes': reverseEpisodes,
        if (flagNames.isNotEmpty) 'flag_names': flagNames,
      };

  factory PlaylistRule.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return const PlaylistRule();
    return PlaylistRule(
      sourceSeparator:
          json['source_separator'] as String? ?? AppConstants.defaultSourceSeparator,
      episodeSeparator:
          json['episode_separator'] as String? ?? AppConstants.defaultEpisodeSeparator,
      nameSeparator:
          json['name_separator'] as String? ?? AppConstants.defaultEpisodeNameSeparator,
      reverseEpisodes: json['reverse_episodes'] as bool? ?? false,
      flagNames: (json['flag_names'] as Map<dynamic, dynamic>? ?? const {})
          .map((k, v) => MapEntry(k.toString(), v.toString())),
    );
  }
}

/// 数据源配置（协议核心对象）。
///
/// 一个 [SourceConfig] 描述「如何与某个具体站点通信」，**不含任何代码**。
/// 客户端的职责是把这份声明式配置解释为具体请求，因此：
/// - 新增源 → 用户导入一份 JSON（热更新，无需发版）；
/// - 源站改版 → 运维侧更新订阅包，客户端拉取即生效。
@immutable
class SourceConfig {
  const SourceConfig({
    required this.key,
    required this.name,
    required this.kind,
    required this.api,
    this.enabled = true,
    this.priority = 100,
    this.searchable = true,
    this.detailable = true,
    this.timeoutMs = 8000,
    this.headers = const <String, String>{},
    this.endpoints,
    this.fields = const FieldMapping(),
    this.playlistRule = const PlaylistRule(),
    this.ext,
    this.group,
    this.icon,
    this.comment,
    this.extra = const <String, dynamic>{},
  });

  /// ── 标识 ────────────────────────────────────────────────
  /// 全局唯一键，建议 `{生态}_{站点}`，如 `maccms_dytt`。
  final String key;

  /// 展示名。
  final String name;

  final SourceKind kind;

  /// 站点根地址（如 `https://api.example.com/api.php/provide/vod/`）。
  final String api;

  /// ── 策略 ────────────────────────────────────────────────
  /// 是否启用。命中该源的搜索/详情都会跳过禁用源。
  final bool enabled;

  /// 优先级，数值**越小越优先**。聚合去重时用于挑选主条目。
  final int priority;

  /// 该源是否支持关键词搜索（部分源仅提供分类浏览）。
  final bool searchable;

  /// 该源是否支持通过 ID 拉取详情。
  final bool detailable;

  /// 单次请求超时。
  final int timeoutMs;

  /// 源站级自定义请求头（UA / Referer / Cookie）。
  final Map<String, String> headers;

  /// ── 协议映射 ────────────────────────────────────────────
  final EndpointTemplate? endpoints;
  final FieldMapping fields;
  final PlaylistRule playlistRule;

  /// TVBox 系的扩展参数（spider 地址、jar 版本号等）。
  final String? ext;

  /// 分组（UI 中用于折叠展示）。
  final String? group;

  final String? icon;

  /// 源站备注 / 免责声明。
  final String? comment;

  /// 协议预留扩展位。
  final Map<String, dynamic> extra;

  // ── 派生 ────────────────────────────────────────────────

  EndpointTemplate get effectiveEndpoints =>
      endpoints ?? EndpointTemplate.defaultsFor(kind);

  Duration get timeout => Duration(milliseconds: timeoutMs);

  /// 该源是否可被本客户端直接使用。
  bool get isUsable => enabled && kind.isClientSupported && api.trim().isNotEmpty;

  /// 构造搜索请求 URL。
  String? buildSearchUrl(String keyword, {int page = 1}) {
    return effectiveEndpoints.render(
      effectiveEndpoints.search,
      <String, String>{
        'api': api,
        'wd': Uri.encodeComponent(keyword),
        'pg': '$page',
        'ext': ext ?? '',
      },
    );
  }

  /// 构造详情请求 URL。
  String? buildDetailUrl(String vodId) {
    return effectiveEndpoints.render(
      effectiveEndpoints.detail,
      <String, String>{
        'api': api,
        'id': Uri.encodeComponent(vodId),
        'ext': ext ?? '',
      },
    );
  }

  /// 构造分类列表请求 URL。
  String? buildCategoryUrl(String typeId, {int page = 1}) {
    return effectiveEndpoints.render(
      effectiveEndpoints.category,
      <String, String>{
        'api': api,
        'tid': Uri.encodeComponent(typeId),
        'pg': '$page',
      },
    );
  }

  /// 完整性校验：返回错误信息列表，为空表示配置合法。
  List<String> validate() {
    final errors = <String>[];
    if (key.trim().isEmpty) errors.add('缺少 key');
    if (name.trim().isEmpty) errors.add('缺少 name');
    if (api.trim().isEmpty) {
      errors.add('缺少 api 地址');
    } else {
      final uri = Uri.tryParse(api);
      if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
        errors.add('api 不是合法的绝对 URL：$api');
      } else if (uri.scheme != 'http' && uri.scheme != 'https') {
        errors.add('api 协议必须是 http/https，当前为 ${uri.scheme}');
      }
    }
    if (searchable && (effectiveEndpoints.search.trim().isEmpty)) {
      errors.add('声明 searchable=true 但缺少 search 端点模板');
    }
    if (detailable && (effectiveEndpoints.detail.trim().isEmpty)) {
      errors.add('声明 detailable=true 但缺少 detail 端点模板');
    }
    if (priority < 0) errors.add('priority 不能为负数');
    if (timeoutMs < 1000) errors.add('timeoutMs 过小（<1000ms），建议 3000~10000');
    if (!kind.isClientSupported) {
      errors.add('数据源类型 ${kind.wire} 需要外置运行时，客户端无法直接解析');
    }
    return errors;
  }

  // ── 序列化 ──────────────────────────────────────────────

  Map<String, dynamic> toJson() => <String, dynamic>{
        'key': key,
        'name': name,
        'kind': kind.wire,
        'api': api,
        'enabled': enabled,
        'priority': priority,
        'searchable': searchable,
        'detailable': detailable,
        'timeout_ms': timeoutMs,
        if (headers.isNotEmpty) 'headers': headers,
        if (endpoints != null) 'endpoints': endpoints!.toJson(),
        'field_map': fields.toJson(),
        'playlist': playlistRule.toJson(),
        if (ext != null) 'ext': ext,
        if (group != null) 'group': group,
        if (icon != null) 'icon': icon,
        if (comment != null) 'comment': comment,
        if (extra.isNotEmpty) 'extra': extra,
      };

  factory SourceConfig.fromJson(Map<String, dynamic> json) {
    final kind = SourceKind.fromWire(json['kind'] as String?);
    return SourceConfig(
      key: (json['key'] as String? ?? '').trim(),
      name: (json['name'] as String? ?? '').trim(),
      kind: kind,
      api: (json['api'] as String? ?? '').trim(),
      enabled: json['enabled'] as bool? ?? true,
      priority: (json['priority'] as num?)?.toInt() ?? 100,
      searchable: json['searchable'] as bool? ?? true,
      detailable: json['detailable'] as bool? ?? true,
      timeoutMs: (json['timeout_ms'] as num?)?.toInt() ?? 8000,
      headers: (json['headers'] as Map<dynamic, dynamic>? ?? const {})
          .map((k, v) => MapEntry(k.toString(), v.toString())),
      endpoints: json['endpoints'] == null
          ? null
          : EndpointTemplate.fromJson(
              (json['endpoints'] as Map).cast<String, dynamic>(),
              kind,
            ),
      fields: FieldMapping.fromJson(
        json['field_map'] == null
            ? null
            : (json['field_map'] as Map).cast<String, dynamic>(),
      ),
      playlistRule: PlaylistRule.fromJson(
        json['playlist'] == null
            ? null
            : (json['playlist'] as Map).cast<String, dynamic>(),
      ),
      ext: json['ext'] as String?,
      group: json['group'] as String?,
      icon: json['icon'] as String?,
      comment: json['comment'] as String?,
      extra: json['extra'] == null
          ? const <String, dynamic>{}
          : (json['extra'] as Map).cast<String, dynamic>(),
    );
  }

  /// 从 TVBox 站点条目转换为本协议配置。
  ///
  /// TVBox `sites` 数组的字段为 `key/name/type/api/searchable/quickSearch/ext`，
  /// 这里做一次**适配层转换**，使 TVBox 生态的订阅包可以被直接导入，
  /// 而无需用户手工重写配置。
  factory SourceConfig.fromTvboxSite(Map<String, dynamic> site) {
    final typeValue = (site['type'] as num?)?.toInt() ?? 1;
    final kind = switch (typeValue) {
      0 || 1 => SourceKind.tvboxJson,
      3 || 4 => SourceKind.tvboxSpider,
      _ => SourceKind.custom,
    };
    return SourceConfig(
      key: 'tvbox_${site['key'] ?? site['name'] ?? 'site'}',
      name: (site['name'] as String? ?? site['key'] as String? ?? '未命名').trim(),
      kind: kind,
      api: (site['api'] as String? ?? '').trim(),
      enabled: typeValue != 3 && typeValue != 4,
      priority: 200,
      searchable: (site['searchable'] as num?)?.toInt() != 0,
      detailable: true,
      headers: (site['header'] as Map<dynamic, dynamic>? ?? const {})
          .map((k, v) => MapEntry(k.toString(), v.toString())),
      ext: site['ext']?.toString(),
      group: site['group'] as String?,
      comment: '由 TVBox 订阅导入（type=$typeValue）',
      extra: <String, dynamic>{'tvboxType': typeValue},
    );
  }

  SourceConfig copyWith({
    String? key,
    String? name,
    SourceKind? kind,
    String? api,
    bool? enabled,
    int? priority,
    bool? searchable,
    bool? detailable,
    int? timeoutMs,
    Map<String, String>? headers,
    EndpointTemplate? endpoints,
    FieldMapping? fields,
    PlaylistRule? playlistRule,
    String? ext,
    String? group,
    String? icon,
    String? comment,
    Map<String, dynamic>? extra,
  }) =>
      SourceConfig(
        key: key ?? this.key,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        api: api ?? this.api,
        enabled: enabled ?? this.enabled,
        priority: priority ?? this.priority,
        searchable: searchable ?? this.searchable,
        detailable: detailable ?? this.detailable,
        timeoutMs: timeoutMs ?? this.timeoutMs,
        headers: headers ?? this.headers,
        endpoints: endpoints ?? this.endpoints,
        fields: fields ?? this.fields,
        playlistRule: playlistRule ?? this.playlistRule,
        ext: ext ?? this.ext,
        group: group ?? this.group,
        icon: icon ?? this.icon,
        comment: comment ?? this.comment,
        extra: extra ?? this.extra,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is SourceConfig && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => 'SourceConfig($key, $name, ${kind.wire}, enabled=$enabled)';
}

/// 订阅包（Subscription）。
///
/// 订阅包是**数据源集合的分发载体**，也是热更新协议的核心：
/// 客户端定期拉取订阅地址，比较 [version]，高于本地即增量合并。
@immutable
class SourceSubscription {
  const SourceSubscription({
    required this.id,
    required this.name,
    required this.url,
    required this.version,
    required this.sources,
    this.updatedAt,
    this.author,
    this.comment,
    this.protocol = AppConstants.protocolVersion,
    this.etag,
    this.lastCheckedAt,
  });

  final String id;
  final String name;

  /// 订阅源地址（远程 JSON 的 URL）。
  final String url;

  /// 订阅包版本号，单调递增。热更新依据此字段判定。
  final int version;

  final List<SourceConfig> sources;

  final DateTime? updatedAt;
  final String? author;
  final String? comment;

  /// 协议版本，如 `moviehub/v1`、`tvbox/1`。
  final String protocol;

  /// HTTP ETag，用于条件请求（304 命中则不重新下发）。
  final String? etag;

  final DateTime? lastCheckedAt;

  SourceSubscription copyWith({
    String? id,
    String? name,
    String? url,
    int? version,
    List<SourceConfig>? sources,
    DateTime? updatedAt,
    String? author,
    String? comment,
    String? protocol,
    String? etag,
    DateTime? lastCheckedAt,
  }) =>
      SourceSubscription(
        id: id ?? this.id,
        name: name ?? this.name,
        url: url ?? this.url,
        version: version ?? this.version,
        sources: sources ?? this.sources,
        updatedAt: updatedAt ?? this.updatedAt,
        author: author ?? this.author,
        comment: comment ?? this.comment,
        protocol: protocol ?? this.protocol,
        etag: etag ?? this.etag,
        lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
      );

  /// 本地元信息（不含 sources，用于轻量比较版本）。
  Map<String, dynamic> toMetaJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'url': url,
        'version': version,
        'updated_at': updatedAt?.toIso8601String(),
        'author': author,
        'comment': comment,
        'protocol': protocol,
        'etag': etag,
        'last_checked_at': lastCheckedAt?.toIso8601String(),
      };

  Map<String, dynamic> toJson() => <String, dynamic>{
        'protocol': protocol,
        'id': id,
        'name': name,
        'url': url,
        'version': version,
        'updated_at': updatedAt?.toIso8601String(),
        if (author != null) 'author': author,
        if (comment != null) 'comment': comment,
        'sources': sources.map((s) => s.toJson()).toList(),
      };

  factory SourceSubscription.fromJson(
    Map<String, dynamic> json, {
    String url = '',
    String? etag,
  }) {
    final rawSources = JsonPath.read(json, 'sources');
    final sources = <SourceConfig>[];

    if (rawSources is List) {
      for (final item in rawSources) {
        if (item is Map) {
          sources.add(
            SourceConfig.fromJson(item.cast<String, dynamic>()),
          );
        }
      }
    }

    // 兼容 TVBox 订阅包：sites 数组
    if (sources.isEmpty) {
      final sites = json['sites'];
      if (sites is List) {
        for (final item in sites) {
          if (item is Map) {
            sources.add(SourceConfig.fromTvboxSite(item.cast<String, dynamic>()));
          }
        }
      }
    }

    return SourceSubscription(
      id: json['id'] as String? ??
          'sub_${DateTime.now().millisecondsSinceEpoch}',
      name: (json['name'] as String? ?? json['title'] as String? ?? '未命名订阅').trim(),
      url: url,
      version: (json['version'] as num?)?.toInt() ?? 1,
      sources: sources,
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
      author: json['author'] as String?,
      comment: json['comment'] as String?,
      protocol: json['protocol'] as String? ?? AppConstants.protocolVersion,
      etag: etag,
    );
  }
}
