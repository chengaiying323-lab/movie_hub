# MovieHub 数据源订阅协议 v1

> 目标：**客户端零站点代码**。所有源站适配都以声明式 JSON 描述，
> 通过订阅导入与热更新生效，新增/修复数据源不需要发布新版本客户端。

---

## 1. 设计原则

| 原则 | 说明 |
|---|---|
| 声明式 | 客户端只内置「协议解释器」，不内置任何站点特化逻辑 |
| 可热更新 | 订阅包带 `version`，客户端比对后增量合并 |
| 用户覆盖优先 | 订阅更新**不会**覆盖用户在本地设置的开关与优先级 |
| 失败隔离 | 单个源配置非法 → 跳过并计数，不影响整包导入 |
| 可观测 | 每源校验输出健康度、延迟、样本标题、失败原因 |

---

## 2. 订阅包结构

```jsonc
{
  "protocol": "moviehub/v1",   // 协议标识；主版本不一致时客户端拒绝导入
  "id": "pack-id",
  "name": "源合集名称",
  "version": 3,                 // 单调递增，热更新依据
  "updated_at": "2026-10-09T10:00:00Z",
  "author": "作者",
  "comment": "备注",
  "sources": [ /* SourceConfig[] */ ]
}
```

### 兼容的外部格式

| 格式 | 识别方式 | 处理 |
|---|---|---|
| TVBox 站点订阅 | 存在 `sites` 数组 | 仅提取 `sites`，逐条转换为 `SourceConfig`；`type=3/4` 标记为 `tvbox_spider` 并**跳过导入**（客户端无 JS/Java 运行时） |
| 裸数组 | 根节点为 `Array` | 按 `SourceConfig[]` 直接解析 |
| 苹果CMS 采集接口 | 不适用 | 通过 `kind: "maccms"` + `api` 指向 `api.php/provide/vod/` |

---

## 3. SourceConfig 字段

### 3.1 标识与策略

| 字段 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `key` | string | 必填 | 全局唯一，建议 `{生态}_{站点}` |
| `name` | string | 必填 | 展示名 |
| `kind` | enum | 必填 | `maccms` / `tvbox_json` / `tvbox_spider` / `custom` |
| `api` | string | 必填 | 站点根地址，必须为 http(s) 绝对 URL |
| `enabled` | bool | `true` | 是否启用 |
| `priority` | int | `100` | **越小越优先**；聚合去重时决定主条目 |
| `searchable` | bool | `true` | 是否支持关键词搜索 |
| `detailable` | bool | `true` | 是否支持详情查询 |
| `timeout_ms` | int | `8000` | 单次请求超时 |
| `headers` | object | `{}` | 源站级请求头（UA / Referer / Cookie） |
| `group` | string | — | UI 分组名 |
| `ext` | string | — | TVBox 系扩展参数 |
| `comment` | string | — | 备注 |

### 3.2 `endpoints` —— 端点模板

用模板字符串描述请求 URL，避免在客户端硬编码 URL 拼接。

**占位符**

| 占位符 | 含义 |
|---|---|
| `{api}` | 数据源根地址 |
| `{wd}` | 搜索关键词（**自动 URL 编码**） |
| `{pg}` | 页码 |
| `{id}` | 资源 ID |
| `{tid}` | 分类 ID |
| `{ext}` | 源的 `ext` 字段 |
| 自定义 | `endpoints.variables` 中的键 |

```jsonc
"endpoints": {
  "search":   "{api}?ac=videolist&wd={wd}&pg={pg}",
  "detail":   "{api}?ac=videolist&ids={id}",
  "category": "{api}?ac=videolist&t={tid}&pg={pg}",
  "variables": { "token": "abc123" }
}
```

> 省略 `endpoints` 时按 `kind` 使用内置默认模板。
> 模板中存在**未定义占位符**时导入校验会直接报错，而不是发出错误请求。

### 3.3 `field_map` —— 字段映射

每项是一到多条 **JSON 路径**，用 `||` 组成回退链，取第一个非空值。

**路径语法**

| 语法 | 示例 |
|---|---|
| 点分路径 | `vod_name`、`data.list`、`cover.url` |
| 数组下标 | `list[0].vod_name` 或 `list.0.vod_name` |
| 多路径回退 | `vod_name\|\|name\|\|title` |
| 根节点 | `$` |

**可映射的目标字段**

`list` `id` `name` `sub_title` `poster` `backdrop` `type_id` `type_name`
`categories` `year` `area` `language` `remarks` `actors` `directors`
`description` `score` `duration` `updated_at` `play_from` `play_url` `detail_url`

> 这是「换一个源 = 换一份 JSON」的实现方式：源站字段叫 `vid`/`title`/`cover.url`，
> 就照实写进 `field_map`，**Dart 代码一行不改**。

### 3.4 `playlist` —— 播放串拆解规则

苹果CMS 的播放数据结构是双层分隔的形状串：

```
play_from = "量子线路$$$闪电线路"
play_url  = "第1集$url1#第2集$url2$$$正片$urlA"
                        ↑剧集分隔      ↑线路分隔
```

| 字段 | 默认 | 说明 |
|---|---|---|
| `source_separator` | `$$$` | 线路分隔符 |
| `episode_separator` | `#` | 剧集分隔符 |
| `name_separator` | `$` | 剧集名与地址的分隔符 |
| `reverse_episodes` | `false` | 是否倒序（部分源站新集在前） |
| `flag_names` | `{}` | 线路标志 → 展示名映射 |

**容错处理（解析层已内置，无需配置）**

1. 分隔符被重复书写（`$$$$`）→ 自动归一为 `$$$`；
2. `play_from` 与 `play_url` 线路数不一致 → 以 `play_url` 为准，缺失名回退 `线路N`；
3. 空分组（连续分隔符）→ 跳过，不产生空线路；
4. 剧集段无 `$` 分界 → 整段视为地址，名称按序号生成；
5. 地址为 `#` / `javascript:` / `<script>` → 视为无效剧集，丢弃。

### 3.5 无需配置的能力（解析层自动处理）

| 项 | 行为 |
|---|---|
| 结构化选集 | 若详情返回 `episodes: [{name,url}]` / `urls` / `playlist`，自动识别为线路，无需 `play_url` |
| 分类字段 | `动作,科幻` / `动作\|科幻` / `动作 科幻` 自动归一为数组 |
| 完整 URL 补全 | `//img.x.com/a.jpg` → 继承 `api` 协议；`/upload/a.jpg` → 拼接 `api` 域名 |
| HTML 清洗 | 简介中的 `<p>` `<br>` 与 HTML 实体自动剥离 |
| 评分归一 | 百分制自动折算为 10 分制 |
| 地区归一 | `大陆`→`中国大陆`、`香港`→`中国香港`、`台湾`→`中国台湾`、`澳门`→`中国澳门` |
| 年份提取 | `vod_year` 缺失时从标题中提取 `(2024)` 之类 |

---

## 4. 客户端处理流程

### 4.1 导入

```
订阅 URL ──► HTTP GET ──► 协议版本校验 ──► 逐源 config.validate()
                                              │
                          ┌───────────────────┼───────────────────┐
                          ▼                   ▼                   ▼
                    配置非法→invalid     类型不支持→skipped    合法→合并
                                              │
                                  用户已有该 key？──否──► added
                                              │是
                                      保留本地 enabled / priority / headers
                                              └──► updated
                                    ──► 持久化 + 写订阅元信息
```

### 4.2 热更新

- 请求携带 `If-None-Match: <etag>`；服务端返回 `304` 时客户端直接短路（`NotModifiedException`）；
- 比较 `version`：`remote.version > local.version` 才判定有更新；
- 更新同样走"保留用户覆盖项"的合并逻辑。

### 4.3 可用性校验

采用**真实探针**而非简单连通性检查——大量源站页面正常但采集接口已关闭。

| 结果 | 判定条件 |
|---|---|
| `invalid` | 静态配置校验失败（零网络成本） |
| `unreachable` | 超时 / 连接失败 / 非 2xx |
| `degraded` | 可连通但探针无有效结果，或延迟 > 5000ms |
| `healthy` | 成功且有有效样本，延迟正常 |

校验同时记录**样本标题**，供人工确认「该源返回的内容是否对版」。

---

## 5. 多源聚合与去重

```
N 个启用源 ──并发(Semaphore 限流)──► 各自解析 ──► SourceSearchReport
                                          │
                                   相关性过滤（标题归一化后互相包含）
                                          │
                              精确键分组：normalize(title) + year
                                          │
                              宽松键合并：再去掉结尾数字
                                    （解决「沙丘2」/「沙丘：第二部」）
                                          │
                                    AggregatedMovie
                             primary 按 优先级 → 线路数据 → 集数 选出
                             线路合并去重，按质量分排序
```

**标题归一化**会去除：全角转半角、标点、`2024` 年份、`1080P/国语/未删减` 等画质与版本后缀、
`第二季/第3部` 季部标记、`全24集/更新至12集` 集数标记、罗马数字转阿拉伯数字。

**失败隔离**：任意源抛出的异常都会在 `_searchSingle` 内被捕获并转为报告，
整轮聚合不会中断。

---

## 6. 版本兼容策略

| 收到协议 | 行为 |
|---|---|
| `moviehub/v1.x` | 接受（主版本一致） |
| `moviehub/v2.x` | **拒绝**，提示升级客户端 |
| `tvbox/1` | 接受（走兼容导入通道） |
| 其它 / 缺失 | 缺失按兼容处理；其它值拒绝 |

---

## 7. 合规与安全提示

本协议仅定义**数据源的声明式描述格式**，不内置、不附带任何第三方站点的
采集逻辑或内容。使用者应自行确保所订阅数据源的合法性，并遵守相应站点的
服务条款与所在地区法律法规。生产环境请优先对接获得内容授权的 API。
