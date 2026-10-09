# MovieHub — 跨平台影视聚合播放客户端

Flutter + Riverpod · 目标平台：**Windows 桌面端** / **iOS 移动端**

| 阶段   | 交付内容                                                                                 | 状态    |
| ---- | ------------------------------------------------------------------------------------ | ----- |
| 第一阶段 | 分层架构 · 数据源协议 · 解析层 · 并发聚合 · 源管理                                                      | ✅     |
| 第二阶段 | 浅色极简 UI 层 · 设计令牌 · 响应式脚手架 · 核心页面                                                     | ✅     |
| 第三阶段 | 三态清单（想看 / 正在看 / 已看）· Hive 本地持久化 · 断点续播 · 资料库三分栏                                      | ✅     |
| 第四阶段 | media_kit 播放内核 · HLS/MP4/MKV · 防盗链请求头注入 · 失败分类与自动重试 · 播放控制层 · 追剧逻辑闭环                 | ✅     |
| 第五阶段 | iOS 工程配置补全 · GitHub Actions 云端未签名 IPA 构建 · Windows 便携版 / Inno Setup 安装包 · iOS 侧载交付指南 | ✅     |
| 第六阶段 | 线路测速与自动择优 · 弹幕 · 投屏与画中画                                                              | ⏳ 未开始 |

播放已完全内嵌：`movie_detail_page` 的「立即播放 / 继续观看」与各列表的续播入口  
统一进入 `PlayerPage`，播放期间由内核位置回调驱动 `reportPosition`，  
5 秒心跳落盘、≥90% 自动转「已看」，退出时 `endSession` 强制补写最后一帧位置。

全平台分发已打通：`tool/package_windows.ps1` 本地出 Windows 便携版 / 安装包，  
`.github/workflows/build-ios.yml` 在 macOS runner 上出**未签名 `.ipa`**  
（无需任何 Apple 证书），下载后用 TrollStore / AltStore / Sideloadly 自签安装。  
详见 **[`docs/BUILD_AND_RELEASE.md`](docs/BUILD_AND_RELEASE.md)**。

> ⚠️ **首次克隆后必做两步**，否则任何构建都会失败：
>
> ```powershell
> powershell -ExecutionPolicy Bypass -File tool/scaffold_platforms.ps1   # 补 ios/ windows/
> python tool/patch_ios_project.py                                       # 补 iOS 工程配置
> ```

---

## 1. 架构总览

```
        ┌──────────────────────────────────────────────┐
        │  presentation   页面 / Widget / Riverpod     │
        │  只依赖 domain 抽象；不含任何 IO             │
        └───────────────────┬──────────────────────────┘
                            │  Failure（不抛底层异常）
        ┌───────────────────▼──────────────────────────┐
        │  domain   Movie / PlaySource / Episode       │
        │   SourceConfig（协议 Model）· 仓储接口 · 用例 │
        │   WatchRecord / HomeFeed · 纯 Dart            │
        └───────────────────▲──────────────────────────┘
                            │  实现接口
        ┌───────────────────┴──────────────────────────┐
        │  data                                        │
        │   parsers   声明式协议 → 领域模型             │
        │   player    领域实体 → 播放请求（含防盗链头）  │
        │   services  并发聚合 / 源管理 / 首页装配      │
        │   adapters  Hive 手写 TypeAdapter（免生成）   │
        │   datasources  remote(HTTP) · local(SP+Hive) │
        │   repositories · mappers                     │
        └───────────────────┬──────────────────────────┘
                            │
        ┌───────────────────▼──────────────────────────┐
        │  core   design(令牌) · errors · network(Dio) │
        │        player(内核抽象 + libmpv 实现) · utils │
        │        constants                              │
        └──────────────────────────────────────────────┘
```

**依赖方向单向向下**：`presentation → domain ← data`，`core` 被各层引用但不反向依赖任何业务层。  
`domain` 绝不依赖 `data`，也绝不依赖 Flutter Widget。

`core/player` 是这条规则的一个刻意例外：它依赖 Flutter Widget（要返回渲染面）、  
依赖 `media_kit`（要解码），但**不认识 `Movie` / `Episode` / `SourceConfig`** ——  
领域实体到播放请求的翻译由 `data/player` 承担（见 §6.1）。

---


## 2. 目录结构

```
movie_hub/
├── pubspec.yaml
├── analysis_options.yaml
├── README.md
├── .github/
│   └── workflows/
│       └── build-ios.yml               # ★ iOS 未签名 IPA 云端构建（第五阶段新增）
├── docs/
│   ├── SOURCE_PROTOCOL.md              # 数据源订阅协议规范（重点）
│   └── BUILD_AND_RELEASE.md            # ★ 打包与发布指南（第五阶段新增）
├── tool/
│   ├── verify_structure.py             # 结构静态校验（无需 Flutter 工具链）
│   ├── scaffold_platforms.ps1          # ★ 生成 ios/ windows/ 平台脚手架
│   ├── patch_ios_project.py            # ★ iOS 工程配置幂等补丁（Info.plist / Podfile / pbxproj）
│   ├── package_windows.ps1             # ★ Windows 一键打包（便携版 / 安装包）
│   └── installer/
│       └── movie_hub.iss               # ★ Inno Setup 安装包脚本（UTF-8 BOM）
├── assets/sample/
│   └── subscription.example.json       # 示例订阅包
└── lib/
    ├── main.dart                       # 入口 + Windows 窗口初始化
    ├── app.dart                        # MaterialApp 根组件（浅色模式）
    │
    ├── core/
    │   ├── constants/app_constants.dart
    │   ├── design/                     # ★ 设计令牌体系（第二阶段新增）
    │   │   ├── app_colors.dart         #   浅色极简色板
    │   │   ├── app_spacing.dart        #   间距 / 圆角 / 描边 / 尺寸
    │   │   ├── app_shadows.dart        #   弥散阴影
    │   │   ├── app_motion.dart         #   时长 / 曲线 / 位移量 / 路由过渡
    │   │   ├── app_typography.dart     #   字阶与语义化文本样式
    │   │   ├── app_layout.dart         #   响应式断点（唯一适配判定源）
    │   │   └── design.dart             #   统一出口
    │   ├── error/
    │   │   ├── failure.dart            # sealed Failure（领域统一错误）
    │   │   └── exceptions.dart         # 数据层内部异常
    │   ├── network/http_service.dart   # Dio 封装：bytes 解码 / 双超时 / 探针
    │   ├── player/                     # ★ 播放内核（第四阶段新增）
    │   │   ├── playback_source.dart    #   内核入参值对象（不认识领域实体）
    │   │   ├── playback_state.dart     #   状态机 + 失败分类 + 不可变状态快照
    │   │   ├── player_config.dart      #   重试 / 超时 / 硬解 / 缓冲策略
    │   │   ├── player_engine.dart      #   ★ 内核抽象（上层只依赖它）
    │   │   ├── media_kit_player_engine.dart  # ★ libmpv 实现（含看门狗与退避重试）
    │   │   ├── player_bootstrap.dart   #   全局初始化生命周期
    │   │   └── player.dart             #   统一出口
    │   └── utils/
    │       ├── json_path.dart          # 声明式字段映射引擎（核心）
    │       ├── title_normalizer.dart   # 标题归一化（去重基础）
    │       ├── html_utils.dart         # HTML 清洗 + URL 补全
    │       ├── semaphore.dart          # 并发闸门
    │       └── id_generator.dart
    │
    ├── domain/                         # 领域层：纯 Dart，无 Flutter / 无 IO
    │   ├── entities/
    │   │   ├── movie.dart              # ★ MovieModel
    │   │   ├── play_source.dart        # ★ 播放线路（qualityScore）
    │   │   ├── episode.dart            # ★ 选集
    │   │   ├── source_config.dart      # ★ 数据源协议
    │   │   ├── source_validation.dart  # 健康度 / 校验结果 / 导入报告
    │   │   ├── search_result.dart      # 聚合条目 / 单源报告 / 聚合结果
    │   │   ├── watch_record.dart       # ★ 观影记录 + 三态状态机 + 聚合状态
    │   │   └── home_feed.dart          # ★ 首页分区与 Feed
    │   ├── repositories/
    │   │   ├── movie_repository.dart
    │   │   ├── source_repository.dart
    │   │   └── watch_history_repository.dart   # ★ 观影记录仓储接口
    │   └── usecases/
    │       ├── search_movies_usecase.dart
    │       ├── get_movie_detail_usecase.dart
    │       └── manage_sources_usecase.dart
    │
    ├── data/
    │   ├── parsers/
    │   │   ├── source_parser.dart      # 解析器抽象（纯函数，不发请求）
    │   │   ├── json_source_parser.dart # ★ 公共基类：字段映射 + 播放串拆解
    │   │   ├── maccms_parser.dart      # 苹果CMS v10
    │   │   ├── tvbox_json_parser.dart  # TVBox JSON / 结构化选集
    │   │   └── parser_registry.dart    # 按 kind 路由，可运行时扩展
    │   ├── player/
    │   │   └── playback_request_builder.dart  # ★ 领域实体 → 播放请求（防盗链头推导）
    │   ├── services/
    │   │   ├── search_aggregator.dart  # ★ 多源并发 + 去重聚合 + 流式
    │   │   ├── source_manager.dart     # ★ 源管理 / 校验 / 热更新
    │   │   └── home_feed_service.dart  # ★ 首页分区装配（含降级链）
    │   ├── adapters/
    │   │   └── watch_record_adapter.dart  # ★ 手写 TypeAdapter（免 build_runner）
    │   ├── datasources/
    │   │   ├── local/
    │   │   │   ├── source_local_datasource.dart   # 源 + 订阅 + 搜索历史（SP）
    │   │   │   └── watch_history_local_datasource.dart  # ★ 观影记录（Hive）+ 旧数据迁移
    │   │   └── remote/source_remote_datasource.dart # 订阅拉取 + 格式嗅探
    │   ├── mappers/failure_mapper.dart # 异常 → Failure 收敛
    │   └── repositories/
    │       ├── movie_repository_impl.dart
    │       └── watch_history_repository_impl.dart   # ★ 薄仓储 + 容量治理
    │
    └── presentation/
        ├── app_navigation.dart         # ★ 统一路由助手（集中过渡动效 + openPlayer）
        ├── providers/
        │   ├── core_providers.dart     # 依赖注入装配（唯一装配点）
        │   ├── source_providers.dart   # 源列表 / 校验 / 订阅 / 按 key 查配置
        │   ├── search_providers.dart   # 搜索流 / 分源过滤 / 详情 family
        │   ├── watch_history_providers.dart  # ★ 三态状态机 + 进度回写 + 续播
        │   ├── player_providers.dart   # ★ 播放策略 + 内核工厂（可覆盖）
        │   └── home_providers.dart     # ★ 首页 Feed（分批加载）
        ├── pages/
        │   ├── home_page.dart          # 响应式外壳（Rail ↔ BottomBar）
        │   ├── discover_page.dart      # 首页：Banner + 继续观看 + 推荐
        │   ├── search_page.dart        # 聚合搜索（流式）+ 分源 Tab
        │   ├── library_page.dart       # 片库：正在看 / 想看 / 已看 三分栏
        │   ├── source_manage_page.dart # 订阅导入 / 批量校验 / 开关
        │   ├── movie_detail_page.dart  # 模糊背景 + 线路切换 + 选集 + 起播入口
        │   └── player_page.dart        # ★ 内嵌播放页（内核 + 历史 + UI 闭环）
        ├── widgets/                    # 设计系统组件（浅色）
        │   ├── adaptive_scaffold.dart  # ★ 跨平台导航外壳
        │   ├── frosted_surface.dart    # 毛玻璃（含全局降级开关）
        │   ├── shimmer.dart            # 骨架屏（ShaderMask，自研）
        │   ├── poster_card.dart        # 海报卡片（hover 浮起 / 右键）
        │   ├── poster_grid.dart        # ★ 网格度量（严格 2:3）
        │   ├── poster_image.dart       # 三态图片（骨架/淡入/占位）
        │   ├── hero_banner.dart        # 焦点图轮播
        │   ├── movie_row.dart          # 横向滑动栏
        │   ├── section_header.dart     # 分区标题
        │   ├── search_capsule.dart     # 搜索胶囊 + 快捷键
        │   ├── continue_watching_row.dart
        │   ├── watch_status_button.dart # ★ 三态按钮（想看/正在看/已看）
        │   ├── confirm_dialog.dart     # ★ 二次确认（危险操作统一入口）
        │   ├── app_menu.dart           # 右键菜单 / 长按菜单
        │   ├── empty_state.dart        # 空态 / 错误态
        │   └── player/                 # ★ 播放层组件（暗色，第四阶段新增）
        │       ├── video_player_component.dart # 渲染 + 手势 + 状态反馈
        │       ├── controls_overlay.dart       # 半透明暗色控制层
        │       ├── player_progress_bar.dart    # 三段式进度条（缓冲/已播/拖拽）
        │       ├── player_speed_menu.dart      # 倍速菜单
        │       ├── player_side_sheet.dart      # 侧滑面板基座（选集/线路共用）
        │       ├── episode_drawer.dart         # 选集抽屉（倒序 + 自动定位当前集）
        │       ├── source_drawer.dart          # 线路抽屉（画质/集数/直链率）
        │       ├── player_error_panel.dart     # 失败浮层（按失败类型定主按钮）
        │       ├── resume_overlay.dart         # 「上次观看到 XX:XX」暗色浮层
        │       └── player_widgets.dart         # 统一出口
        └── theme/
            ├── app_theme.dart          # 浅色极简 ThemeData
            └── player_palette.dart     # ★ 播放层暗色令牌（与主题解耦）
```

---

## 3. 阶段一：数据层关键设计

### 3.1 为什么不用 `json_serializable` 硬编码字段

影视源的字段名在苹果CMS、TVBox、自建 API 之间高度不一致。  
若把 `vod_name` 写死在 `fromJson` 中，每适配一个新源就要改代码并发版——  
这正是"爬虫逻辑硬编码在客户端"的反模式。

本方案把字段映射抽为 `FieldMapping`（形如 `vod_name||name||title` 的路径回退链），  
由 `JsonPath` 在运行时求值。**新增源 = 新增一份 JSON**。

### 3.2 解析层与网络层分离

`SourceParser` 只做「JSON → 领域模型」的纯函数转换，不发请求。  
好处：可以直接用固定 fixture 做单元测试，不需要 mock 网络。

### 3.3 播放串拆解是协议而非代码

`$$$` / `#` / `$` 三处分隔符全部由 `PlaylistRule` 声明，并内置 5 类容错。  
源站改版只需改订阅包。

### 3.4 聚合必须"失败隔离 + 可观测"

`SearchAggregator._searchSingle` 捕获全部异常并转为 `SourceSearchReport`，  
整轮搜索永不因单源失败而中断；同时把每源的耗时、原始条数、失败原因  
透传到 UI——用户需要知道"结果为什么变少了"。

### 3.5 去重采用两轮键

| 轮次 | 键                         | 解决              |
| -- | ------------------------- | --------------- |
| 精确 | `normalize(title) + year` | 标点/画质后缀/全角差异    |
| 宽松 | 去掉结尾数字 + year             | 「沙丘2」vs「沙丘：第二部」 |

---

## 4. 阶段二：UI 层设计

### 4.1 浅色极简视觉规范

**背景层级模型（由低到高）**

| 层级              | 色值              | 用途                   |
| --------------- | --------------- | -------------------- |
| `canvas`        | `#F5F6F8`       | 页面主底色（米白灰，长时间浏览不刺眼）  |
| `canvasWarm`    | `#F7F8FA`       | Banner 渐变落点等需轻微区分的区域 |
| `surfaceMuted`  | `#EFF1F4`       | 输入框、标签底、骨架屏基底        |
| `surfaceSunken` | `#E8EAEE`       | 进度槽、凹陷容器             |
| **`surface`**   | **`#FFFFFF`**   | **唯一纯白，仅用于卡片层级**     |
| `frosted`       | `#FFFFFF` @ 72% | 毛玻璃浮层                |
| `frostedStrong` | `#FFFFFF` @ 85% | 移动端底部栏（保证文字可读）       |

> 核心约束：**纯白只承载"内容单元"的心智**。页面底色永远是灰白，避免大面积高反差。

**描边统一用透明黑而非实色灰**：`hairline = #14000000`（8% 黑，0.8dp），  
`hairlineStrong = 12%`，`hairlineSubtle = 5%`。  
好处是叠加在任何底色上都呈现一致的"极细发丝线"观感。

**强调色**：`accent = #E8543F`（柔和珊瑚红），配 `accentSoft`(8%) / `accentSofter`(4%)  
两级淡背景表达选中与悬停，避免色块刺眼。状态色另有 `positive` / `danger` / `warning` 及其 soft 变体。

**海报卡片**：严格 2:3（`AppSizes.posterAspectRatio = 2/3`）、圆角 14dp、  
`AppShadows.card`（黑 4% + 位移 2dp 的弥散阴影）+ 0.8dp 发丝描边双重收边。

**图片三态**（`PosterImage`）：加载中 → 淡灰骨架屏（Light Shimmer）；  
成功 → 淡入；失败/空 → 低饱和渐变占位（`posterPlaceholderGradient`）+ 极简图标。

### 4.2 设计令牌体系

所有视觉常量集中在 `core/design/`，页面与组件**禁止写魔法数字**。

| 令牌              | 内容                                                                                                                                                       |
| --------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `AppColors`     | 背景层级 / 描边 / 文字 / 强调 / 状态 / 骨架 / 阴影基色                                                                                                                     |
| `AppSpacing`    | 4pt 栅格：`xxs 4` `xs 8` `sm 12` `md 16` `lg 24` `xl 32` `xxl 48`；`pageHPadding` 移动 16 / 桌面 32                                                              |
| `AppRadius`     | `card 14` `panel 18` `large 22` `pill 999` + 预置 `BorderRadius`                                                                                           |
| `AppStroke`     | `hairline 0.8`                                                                                                                                           |
| `AppSizes`      | `posterAspectRatio 2/3` `railWidth 84` `railWidthExpanded 208` `bottomBarHeight 62` `bottomBarMargin` `bannerHeightDesktop 340` `rowTextExtent 46`       |
| `AppShadows`    | `card`(4%) `cardHover`(8%, 浮起 4dp) `cardPressed` `overlay` `frostedBar` `textOnImage` `tinted()` `brand`                                                 |
| `AppMotion`     | `instant 120` `fast 180` `normal 260` `slow 420` `shimmer 1400` `bannerAutoPlay 6s`；曲线 `standard/emphasized/soft/decelerate`；`hoverLift 4` `pressSink 1` |
| `AppTypography` | `textTheme` + 语义样式 `posterTitle 13.5` `posterMeta 11.5` `sectionTitle 17` `badge 10.5` `detailTitle 28` `button` `episode`                               |

### 4.3 响应式断点与导航形态

`AppLayout` 是**跨平台适配的唯一判定源**——页面内禁止出现  
`MediaQuery.sizeOf(context).width > 900` 这类散落判断。

| 宽度            | 场景        | 海报列数 | 导航形态            | 滑动栏单屏 |
| ------------- | --------- | ---- | --------------- | ----- |
| `< 600`       | 手机竖屏      | 2    | 底部毛玻璃栏          | 2     |
| `600 ~ 900`   | 手机横屏 / 小窗 | 3    | 底部毛玻璃栏          | 3     |
| `900 ~ 1240`  | 桌面窄窗      | 4    | 左侧悬浮栏（图标态 84dp） | 5     |
| `1240 ~ 1560` | 桌面标准      | 5    | 左侧悬浮栏（展开 208dp） | 6     |
| `≥ 1560`      | 桌面宽屏      | 6    | 左侧悬浮栏（展开 208dp） | 6     |

`900dp` 是形态切换点：`isDesktop` 决定用左侧悬浮侧边栏还是底部悬浮标签栏。  
侧边栏是**四周留白 + 圆角 + 阴影的悬浮卡片**（而非贴边面板），这是浅色极简风格的关键细节。

### 4.4 安全区适配

| 形态          | 处理                                                                                                                       |
| ----------- | ------------------------------------------------------------------------------------------------------------------------ |
| iOS 移动端     | 底部栏外包 `SafeArea(top: false, minimum: EdgeInsets.only(bottom: margin))`，自动让出 Home 指示条；顶部灵动岛由各页面 `MediaQuery.paddingOf` 处理 |
| Windows 桌面端 | 无安全区，窗口最小尺寸 960×640（`main.dart` 对齐 `AppLayout.medium` 断点）                                                                |

**`AppScaffoldInsets`（InheritedWidget）**：把导航栏占用的高度向下传递。  
页面通过 `AppScaffoldInsets.bottomOf(context)` 取到后加到滚动区 `padding.bottom`，  
从而**内容可以滚动到毛玻璃导航栏下方**（毛玻璃才有可模糊的对象），  
又不会让最后一行内容被永久遮挡。这是"悬浮导航 + 毛玻璃"这一组合的必备配套。

### 4.5 跨平台交互差异

| 能力    | 桌面端（键鼠）                                                  | 移动端（触控）                                        |
| ----- | -------------------------------------------------------- | ---------------------------------------------- |
| 悬停    | `MouseRegion` → 卡片上浮 4dp + 阴影加深 + 悬停播放按钮淡入               | 无（触控无 hover 态）                                 |
| 菜单    | 右键 `onSecondaryTapDown` → `showMenu` 浮动菜单                | 长按 `onLongPressStart` → `showModalBottomSheet` |
| 横向栏翻页 | 整栏悬停时左右箭头淡入                                              | 纯手势滑动                                          |
| 键盘    | `Ctrl/Cmd + K` 聚焦搜索、`/` 聚焦、`Esc` 清空（`CallbackShortcuts`） | 无                                              |
| 光标    | `SystemMouseCursors.click` / 自定义光标                       | 无                                              |
| 路由过渡  | `FadeUpwards`（Windows 默认偏硬）                              | `Cupertino`                                    |

统一入口是 `AppMenu.showFor` 与 `PosterCard.withAppMenu` 扩展，页面无需感知平台。

### 4.6 核心页面结构

**首页（发现）** `discover_page.dart`

```
顶部浅色半透明渐变焦点图（HeroBanner：PageView 自动轮播 + 悬停暂停 + 指示圆点）
  └ 双层浅色渐变：垂直融入 canvas + 水平左侧底衬（保证标题在任何海报上都可读）
继续观看进度浮层（ContinueWatchingRow，仅当有观看记录时出现）
热门推荐分区 × N（MovieRow 横向滑动栏，分区独立容错）
```

性能策略：首屏只加载前 3 个分区，滚动 600px 时预加载剩余分区。

**搜索页** `search_page.dart`

```
轻质圆角搜索胶囊（聚焦时描边转品牌色 + 光晕，尺寸不变避免跳动）
流式细进度条（searchStreamingProvider）
结果工具条：流式/极速开关 + 分源 Tab（失败源排到最后并标红）
结果海报网格 / 历史搜索标签（胶囊 chip，可单个删除）
```

接入阶段一的 `searchStream`：每完成一个源就刷新一次 UI，用户无需等待最慢的源。  
分源 Tab 由 `sourceFilterOptionsProvider` 从 `SourceSearchReport` 派生，  
过滤时把 `primary` 换成该源的变体，保证卡片角标与所选 Tab 一致。

**影视详情页** `movie_detail_page.dart`

```
_BlurredBackdrop  三层结构：
   ① ImageFiltered 高斯模糊的背景海报
   ② BackdropFilter 浅色半透明毛玻璃蒙层
   ③ 向 canvas 的垂直渐变（与页面底色无缝衔接）
_InfoSection      标题 / 评分 / 类型 / 简介（展开折叠）/ 一键追剧
_PlayPanel        线路 chips（按 qualityScore 排序）+ 选集网格（>60 集折叠）
```

**片库页** `library_page.dart`：继续观看网格 + 追剧网格 + 空态 + 清空进度。

**数据源页** `source_manage_page.dart`：所有操作区 + 订阅区（检查更新/单独更新）

- 源列表卡片（健康度指示灯 / kind 标签 / 开关 / 优先级 / 删除）。

### 4.7 关键实现细节

**① 海报网格为何显式计算高度**  
卡片 = 海报（2:3）+ 固定高度文字区。若用 `childAspectRatio`，文字区高度会随卡片  
宽度线性缩放 → 窄屏文字压扁、宽屏大片空白。因此显式：  
`mainAxisExtent = itemWidth / (2/3) + rowTextExtent(46)`，  
保证**海报始终严格 2:3、文字区高度恒定**。

**② 毛玻璃必须置于 `ClipRRect` 内**  
`BackdropFilter` 会模糊其下已绘制内容；不裁剪会导致模糊溢出圆角。  
`FrostedSurface` 统一封装，并提供全局 `blurEnabled` 降级开关  
（集显 Windows 设备可整体关闭模糊，避免掉帧）。

**③ 骨架屏自研，不引第三方包**  
`ShaderMask` + `BlendMode.srcATop` + 移动线性渐变（`shimmer 1400ms` 循环），  
`SkeletonBox` / `PosterSkeleton` / `TextBlockSkeleton` 三种预设。  
骨架数量与列数对齐，保证"骨架 → 内容"过渡不跳动。

**④ 片库乐观更新 + 失败回滚**  
`WatchHistoryNotifier` 先改 UI 再落盘，失败时回滚到上一次快照并重新抛出，  
避免"点了标记却没生效"的静默失败。UI 侧统一用 `runWatchAction` 执行变更，  
把回滚异常收敛成一条可读的失败提示，而不是无人接收的异步错误。

**⑤ 搜索流不用 `AsyncValue.loading` 表达"进行中"**  
流式搜索过程中 `state` 会被反复写入 `data`。若用 loading 表达进行中会导致内容闪烁，  
因此单独用 `searchStreamingProvider` 驱动顶部细进度条。

---

## 5. 阶段三：观影状态追踪与本地持久化

目标：**想看 / 正在看 / 已看** 三态清单 + 断点续播，完全离线可用，  
并复用第二阶段已有的 `PosterCard` / `SliverPosterGrid` / `AppMenu` 等设计系统组件。

### 5.1 存储选型：按数据形态分工，而不是"全局统一一个库"

| 数据                | 形态特征                      | 选择                   |
| ----------------- | ------------------------- | -------------------- |
| 数据源配置 / 订阅 / 搜索历史 | 条目少、结构扁平、**整块读写**         | `shared_preferences` |
| 观看记录              | 条目多、需要**按 key 增量更新与倒序查询** | **`hive`**           |

对「观看记录」这一类的候选评估：

| 候选                   | 结论                                                                       |
| -------------------- | ------------------------------------------------------------------------ |
| `shared_preferences` | ✗ 只能整块读写字符串列表，"改一条要重写全部"，随记录数增长明显变慢                                      |
| `sqflite`            | ✗ Windows 需额外引入 `sqflite_common_ffi` + `sqlite3_flutter_libs` 并手动初始化 FFI |
| `isar`               | ✗ v3 需 `build_runner` 代码生成，且对新版 Flutter 兼容性反复                            |
| **`hive`**           | ✓ 纯 Dart、Windows/iOS 开箱可用、Box 按 key 索引，**配手写适配器则完全免代码生成**                |

`pubspec.yaml` 相关依赖：

```yaml
shared_preferences: ^2.2.3   # 源配置 / 订阅 / 搜索历史
hive: ^2.2.3                 # 观影记录
hive_flutter: ^1.1.0         # 平台目录初始化（Hive.initFlutter）
path_provider: ^2.1.3        # hive_flutter 的传递依赖，显式声明便于审计
```

**无需任何额外配置**：`main()` 中调用一次 `WatchHistoryLocalDataSource.initialize()`  
（内部 `Hive.initFlutter()` + 注册适配器）即可；不使用 `build_runner`，  
因此仓库里不存在 `.g.dart` 文件。

### 5.2 免代码生成的手写 TypeAdapter

`data/adapters/watch_record_adapter.dart` 用 `BinaryReader.readMap()` /  
`BinaryWriter.writeMap()` 直接读写 `WatchRecord.toMap()` 得到的**扁平 Map**：

```dart
const int kWatchRecordTypeId = 7;   // typeId 全局唯一，发布后不可更改

class WatchRecordAdapter extends TypeAdapter<WatchRecord> {
  @override
  WatchRecord read(BinaryReader reader) => WatchRecord.fromMap(reader.readMap());

  @override
  void write(BinaryWriter writer, WatchRecord obj) =>
      writer.writeMap(obj.toMap());
}
```

换来三个好处：

1. **零生成物**：改字段不需要跑 `build_runner`，也没有 `.g.dart` 需要提交；
2. **字段演进天然宽松**：少键取默认值，不会像定长字段流那样抛 `RangeError`；
3. **domain 零依赖**：`WatchRecord` 是纯 Dart，不引入 Hive 注解。

### 5.3 `WatchRecord`：一条记录承载三态

拆成"进度表 + 收藏表"会导致同一影片出现两条互不同步的数据；  
「想看」与「正在看」在用户心智里本来就是同一份清单的不同阶段。

```dart
enum WatchStatus {
  wantToWatch('want_to_watch', '想看'),
  watching('watching', '正在看'),
  watched('watched', '已看');
}
```

三个关键决策：

- **唯一键 `{sourceKey}:{vodId}`**（`WatchRecord.id`）。同一部影片在不同源站的  
  线路地址不通用（换源后需重新定位集数），因此键里必须带源。该键派生自  
  `sourceKey` + `vodId` 而非独立存储，避免"键与内容不一致"的脏数据。
- **持久化用字符串 `storageKey` 而非 `enum.index`**。一旦后续在中间插入枚举值，  
  按索引落盘的旧数据会被错误映射到别的状态。
- **`watched` 不是终态**。进度写入的状态机只有两个分支：
  ```
  进度 ≥ 90%  →  watched
  其它        →  watching
  ```
  因此已看条目被从头重播时会自然回到 `watching`，「继续观看」重新出现，  
  不会变成无法打破的死状态。

`WatchHistoryState` 一次性持有全量记录并 `late final` 预分组  
（`watching` / `wantToWatchList` / `watched` / `resumable`）与 `movieId` 索引，  
避免三个 Tab 各自遍历全表。

### 5.4 进度回写：5 秒心跳 + 脏标记

```
beginSession()  ──► 落一次「起播点」+ 启动 Timer.periodic(5s)
      │
      ▼
reportPosition() ──► 只更新内存样本；变化 < 2000ms 不置脏
      │
      ▼
   flush()      ──► 心跳触发；脏才写盘，失败保留脏标记下次重试
      │
      ▼
 endSession()   ──► 停心跳 + flush(force: true) 兜底
```

`updateProgress()` 是一次性写入入口（无需先 `beginSession`），  
供内嵌播放器或外部上报只拿到单个时间点的场景使用。

**当前阶段的实际用法**：播放动作由系统外部播放器（`url_launcher`）承接，  
播放位置无法回传本应用，因此 `movie_detail_page` 走  
`beginSession` → 调起播放器 → `endSession`，只落一次起播记录。  
接入内嵌播放器后，在播放中持续调用 `reportPosition` 即可自动获得周期性回写。

### 5.5 断点续播

`movie_detail_page` 的 `_play` 是三段式流程：

```
① 续播询问 ──► ② 建立会话并落盘 ──► ③ 交给外部播放器
```

- **只在"同一线路 + 同一集"时才询问**：用户主动切到别的集，  
  显然是要从头看那一集，拿另一集的进度去问很不合理；
- **「继续观看」按钮不二次询问**（`askResume: false`）：按钮文案已经是  
  「继续观看 · 第 N 集」，用户点它就是要续播；
- **「从头播放」必须真正生效**：`beginSession(restart: true)` 会让  
  "同集则沿用旧进度"的规则失效，否则用户点了等于没点；
- **冷启动竞态防护**：`getLastWatchRecord` 是纯内存读，首屏 Hive 读取未完成时  
  会返回 null。`_resolveLastRecord` 在不命中时 `await` 一次加载再判定，  
  避免"明明有进度却不弹续播"。

判据集中在 `WatchRecord.shouldResume`，排除两类噪声：刚点开就退出  
（进度 < 1% 且仍是第 1 集）、已看完的条目。

### 5.6 资料库页（三分栏）

`LibraryPage` = 头部统计 + 清空入口 + `TabBar`（顺序即 `WatchStatus.tabOrder`：  
**正在看 / 想看 / 已看**）+ 三个独立 `CustomScrollView`（各自保留滚动位置）。

卡片叠加信息随状态变化：

| 分栏  | 卡片附加信息                   | 点击行为     |
| --- | ------------------------ | -------- |
| 正在看 | 底部进度条 + `第 3 集 · 已看 65%` | 直接在详情页续播 |
| 想看  | 无                        | 进详情      |
| 已看  | 左上「已看」角标                 | 进详情      |

快捷操作：桌面端右键 / 移动端长按弹快捷菜单；左滑 `Dismissible` 移除。  
**左滑用 `confirmDismiss` 先确认、`onDismissed` 再删除**——  
若在 `confirmDismiss` 里直接删数据，会出现"已经 dismiss 但 widget 仍在树中"  
的框架断言。

### 5.7 容量治理与旧数据迁移

- **上限 500 条**：每次 `upsert` 后做一次 O(1) 的 `Box.length` 检查，  
  超限才真正淘汰。淘汰优先级 `已看 → 想看 → 正在看`，同权重按 `updatedAt`  
  最旧优先——保证「正在看」不会被自动清理。
- **旧数据迁移**：`migrateLegacyIfNeeded()` 把第二阶段的  
  `shared_preferences` 键（`watch_progress.v1` / `favorites.v1`）搬进 Hive。  
  幂等（写迁移标记）、**绝不覆盖新库已有键**、单条脏数据跳过而不中断整体、  
  迁移后删除旧键。迁移失败不影响启动（`main.dart` 吞异常并 `debugPrint`）。
- **离线冗余**：`posterUrl` / `title` 随记录一起存储，  
  即使所有数据源失效，资料库仍可完整渲染。

### 5.8 Provider 一览

| Provider                    | 类型                      | 用途                   |
| --------------------------- | ----------------------- | -------------------- |
| `watchHistoryProvider`      | `AsyncNotifierProvider` | 状态机 + 进度回写 + 加载      |
| `watchHistoryStateProvider` | `Provider`              | 全量状态（三分栏 / 计数）       |
| `resumeListProvider`        | `Provider`              | 首页「继续观看」（最多 12 条）    |
| `watchActiveCountProvider`  | `Provider`              | 侧边栏角标（正在看 + 想看，不含已看） |
| `watchRecordProvider`       | `Provider.family`       | 某影片的记录（续播判定入口）       |
| `watchStatusProvider`       | `Provider.family`       | 某影片的当前状态             |

`WatchHistoryNotifier` 的公开方法：

```dart
// 状态切换
Future<void> setStatus(Movie movie, WatchStatus status)
Future<void> markWatching(Movie movie)
Future<void> markWatched(Movie movie)
Future<void> remove(String movieId)
Future<int>  removeByStatus(WatchStatus status)
Future<void> clear()

// 进度回写
Future<void> beginSession({required Movie movie, required PlaySource source,
                           required Episode episode,
                           int startPositionMs = 0, bool restart = false})
void         reportPosition({required int positionMs, required int durationMs})
Future<void> flush({bool force = false})
Future<void> endSession()
Future<void> updateProgress({required Movie movie, required int positionMs,
                             required int durationMs, ...})

// 查询（同步，不触发 IO）
WatchRecord? getLastWatchRecord(String movieId)
```

---

## 6. 阶段四：播放内核与控制层

### 6.1 内核选型与"两段式解耦"

选 `media_kit`（底层 libmpv）而不是 `video_player` 或 `chewie`：

| 方案              | Windows                  | HLS      | 自定义请求头                | 结论 |
| --------------- | ------------------------ | -------- | --------------------- | -- |
| `video_player`  | 需自行接 MF/DS 后端，能力受限       | 依赖平台     | ❌ 无法注入                | ✗  |
| `chewie`        | 只是 `video_player` 的 UI 壳 | 同上       | ❌                     | ✗  |
| **`media_kit`** | 内置 libmpv，硬解开箱可用         | ✅ mpv 原生 | ✅ `Media.httpHeaders` | ✓  |

影视聚合场景有两个硬需求：**HLS 必须稳**、**请求头必须能改**。  
后者是决定性的 —— 直链几乎从不裸奔（见 §6.3）。

内核对上层只暴露一个抽象：

```dart
abstract class PlayerEngine {
  ValueListenable<PlaybackState> get state;   // 单一状态快照
  Future<void> open(PlaybackSource source, {bool autoPlay = true});
  Future<void> play(); pause(); togglePlay();
  Future<void> seek(Duration); seekBy(Duration);
  Future<void> setRate(double); setVolume(double);
  Future<void> retry(); stop();
  Widget buildVideo({BoxFit fit});            // 抽象工厂，不泄漏 VideoController
  Future<void> dispose();
}
```

**两段式解耦**（本阶段最重要的一条架构决策）：

```
domain 实体                 data 翻译层                    core 内核
Movie + PlaySource    ──►   buildPlaybackRequest()   ──►  PlaybackSource
+ Episode + SourceConfig      · 推导 UA/Referer/Cookie        （值对象）
                              · 判定直播 / 媒体类型
```

- `core/player` **不认识 `Movie` / `Episode`** —— 换内核不必动领域模型；
- `data/player` 承担防盗链头的推导（那是**数据源协议知识**，不是播放知识）；
- 翻译是**纯函数**，单测不需要起播放器。

`buildVideo()` 返回 `Widget` 而不是暴露 `VideoController`：后者会把  
media_kit 的类型泄漏到所有调用点，换内核就得改一圈。

### 6.2 全局初始化生命周期

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Future.wait(<Future<void>>[
    PlayerBootstrap.ensureInitialized(),          // 必须早于 runApp
    WatchHistoryLocalDataSource.initialize(),
  ]);
  runApp(const ProviderScope(child: MovieHubApp()));
}
```

`MediaKit.ensureInitialized()` 会加载各平台原生库（Windows 是 `libmpv-2.dll`  
全家套件，iOS 是打包进 framework 的静态库）并注册平台通道。  
**晚于任何 `Player` / `VideoController` 构造就会直接抛原生库找不到**，  
因此时序不能挪。

**刻意不预热内核实例**：`VideoController` 的构造会立刻创建原生渲染面  
（Windows 上是 D3D 纹理，iOS 上是 Metal 纹理 —— media_kit 在 iOS 走的是  
libmpv/MPVKit 而非 AVPlayerLayer），预热等于"开应用就占一份解码资源"，  
而收益只有几十毫秒 —— 播放页本身还要走网络请求，这点时间被完全掩盖。  
**用复杂度换不到可感知的收益，就不做。**

**不做全局 shutdown**：Windows 关窗、iOS 进后台都可能是进程被挂起而非正常退出，  
没有可靠的统一销毁时机。每个播放页在 `dispose` 里销毁自己持有的内核，  
进程退出由系统回收；这样也天然支持将来的画中画 / 小窗预览（多实例并存）。

### 6.3 流媒体协议、防盗链与请求头注入

**媒体类型判定**（`MediaKind.fromUrl`）有个容易踩的坑：

```text
https://cdn.com/hls/index.m3u8?auth=xxx     → 先匹配 '?' 之前的路径段 → hls ✓
https://cdn.com/play.php?type=m3u8&id=1     → 路径段不匹配，再查查询串 → hls ✓
https://cdn.com/video/tips                  → 后缀匹配必须带前导 '.'，否则误判 .ts ✗
```

`unknown` 是重要信号：说明源站给的是**需要二次解析的页面地址**，  
播放器必然失败，应当直接提示"换线路"而不是傻等超时。

**请求头注入的优先级**（`buildPlaybackHeaders`，后者覆盖前者）：

| 顺序 | 来源                                                     | 说明                                |
| -- | ------------------------------------------------------ | --------------------------------- |
| 1  | 由播放地址推导 `Referer` / `Origin`                           | 最后兜底，通常无效（防盗链校验的是"页面来源"而非"资源所在域"） |
| 2  | `SourceConfig.api` 的 origin                            | 源站页面来源，白名单校验命中率最高                 |
| 3  | `SourceConfig.extra`（`referer` / `cookie` / `headers`） | 协议扩展位，给特殊源站兜口子                    |
| 4  | **`SourceConfig.headers`**                             | 源站声明的头，最高优先级                      |
| 5  | 缺失 `User-Agent` 时补兜底 UA                                | 大量 CDN 对空 UA 直接 403               |

`Origin` 按 CORS 规范**不带路径与末尾斜杠**，`Referer` 则保留路径 ——  
两者推导规则不同，因此在 `_originOf(url, keepPath:)` 里显式区分。

**续播位置不写进 `open` 参数**：多数内核在 `open` 完成前 Seek 会被丢弃。  
因此 `PlaybackSource.startPositionMs` 只是**携带**这个值，  
由实现在拿到 `duration` 后执行一次 Seek：

```dart
void _tryApplyResume() {
  if (_pendingResumeMs <= 0) return;
  final total = _state.value.duration;
  if (total <= Duration.zero) return;                 // 时长未知 → 等下一次
  _pendingResumeMs = 0;
  final target = Duration(milliseconds: pending);
  if (target >= total - const Duration(seconds: 5)) return;  // 已到片尾 → 从头
  unawaited(_player.seek(target));
}
```

### 6.4 把散落的多个流收敛成单一状态机

libmpv 给出的是**多个独立布尔流**：`playing` / `buffering` / `completed` /  
`error` / `position` / `duration` / `width` / `height` / `rate` / `volume` / `buffer`。  
而 UI 需要的是**单一枚举**。这里用一个唯一的判定点把它们收敛：

```dart
PlaybackStatus _resolveStatus() {
  if (_failed)    return PlaybackStatus.failed;
  if (_completed) return PlaybackStatus.completed;
  if (_opening)   return PlaybackStatus.opening;
  if (_buffering) return PlaybackStatus.buffering;
  if (_mpvPlaying) return PlaybackStatus.playing;
  if (_current == null) return PlaybackStatus.idle;
  return PlaybackStatus.paused;
}
```

`buffering` 是**独立状态**而不是 `playing` 的一个布尔位：  
"卡住了"和"正常播放"在 UI 上表现完全不同（前者要出加载圈并启动断流检测），  
用布尔位表达会让调用方到处写 `if (playing && buffering)` 这类容易写错的组合判断。

**`PlaybackState` 绝不流经 Riverpod 全局 state**：位置回调可达 10Hz，  
把它桥接进全局 state 会让整棵订阅树按帧重建。UI 侧一律用  
`ValueListenableBuilder`，只重建时间标签与进度条；播放页的回调里  
只做"把位置赋给 Notifier 的内存样本"这一件极轻的事。

`PlaybackState` 实现了值相等 —— `ValueNotifier` 用 `==` 判重，  
libmpv 会重复上报同一个 `buffering=false`，没有值相等就会白白触发一轮重建。

### 6.5 失败分类、断流看门狗与指数退避重试

**为什么必须分类**：用户能做的动作只有三种 —— 重试、换线路、放弃。  
分类的作用就是决定哪个该高亮：

| 失败类型              | 重试有意义    | 建议换线路 | UI 主按钮 |
| ----------------- | -------- | ----- | ------ |
| 403 / 401（防盗链、鉴权） | ❌        | ✅     | 换线路    |
| 404 / 410         | ❌        | ✅     | 换线路    |
| 地址需二次解析           | ❌        | ✅     | 换线路    |
| 格式不支持             | ❌        | ✅     | 换线路    |
| 解码失败              | ✅（关硬解再试） | ✅     | 换线路    |
| 超时 / 断流           | ✅        | ❌     | 重试     |
| 网络不可达             | ✅        | ❌     | 重试     |

分类靠**关键词匹配**而非错误码：libmpv 下发的 `stream.error` 是  
**人类可读字符串**（`HTTP error 403` / `Failed to open https://…`），  
不同平台与 mpv 版本的措辞还不完全一致。匹配按"最具体的特征优先"排列，  
全部落空归入 `unknown`；另外还有一条比报错文本更可靠的判据：  
**地址本身不像直链 → 直接归为"需解析"**。

**断流看门狗**（本内核最容易被忽略、但最关键的一环）：

`stream.error` 只能覆盖"内核明确报错"的情况。而弱网/防盗链最常见的失败形态是  
**既不报错也不推进** —— TCP 连上了、但服务端一直不发数据。  
没有看门狗，UI 会永远停在转圈上。因此：

- 起播 / 重试：`openTimeout`（25s）内没拿到时长或首帧 → 判失败；
- 播放中：位置停止推进超过 `stallTimeout`（20s）→ 判为断流失败；
- 位置每推进一次就重置计时器，但做 **1 秒节流**（回调 10Hz，  
  每秒重建 10 个 `Timer` 毫无意义；最坏后果只是晚 1 秒发现断流）。

**指数退避自动重试**：`base × 2^(n-1)`，0.8s → 1.6s → 3.2s，上限 3 次。  
三个条件同时成立才自动重试：这一类比值得重试、还有重试余额、  
用户仍在等这集播起来（已暂停时不必后台重连）。

**解码失败降级软解**：解码失败的头号嫌疑是硬解兼容性，  
因此在重试判定**之前**先 `setProperty('hwdec', 'no')`，让紧接着的重试用软解跑。  
之所以用 `setProperty` 而不是重建 `VideoController`：后者的  
`enableHardwareAcceleration` 只在构造时生效，改它得重建整个渲染面。

自动重试期间 `failure` **非空但 `status == opening`**：  
UI 只在 `status == failed` 时弹出可操作的错误面板，  
重试期间只显示一条"连接不稳定，正在自动重试（第 N 次）"。

### 6.6 追剧与历史逻辑闭环

```text
PlayerPage.initState
  ├─ 创建内核（生命周期 = 播放页）
  ├─ WakelockPlus.enable()   防息屏
  └─ postFrame → _bootstrap()
       ├─ 解析线路与选集（缺省回退到第一条可用线路）
       ├─ 读观看记录（冷启动竞态安全：不命中时 await watchHistoryProvider.future）
       ├─ 命中「同线路同集且未看完」→ 暗色续播浮层（一键 Seek / 从头播放 / 取消即退出）
       ├─ beginSession()   ← 记录立即落盘，「正在看」当场生效
       └─ engine.open()    ← 携带防盗链请求头

播放中
  └─ engine.state 监听 → reportPosition()   ← 5 秒心跳由 Notifier 负责落盘

结束
  ├─ 播完 → flush(force: true)  ← 位置 ≥90%，状态自动转「已看」
  └─ dispose → endSession()     ← 强制补写最后一个位置
```

**续播判定的唯一依据**是 `WatchRecord.matchesEpisode(sourceFlag:, episodeIndex:)`，  
它被两处共享：`beginSession`（决定新会话是否沿用旧进度）与播放页  
（决定把哪个位置写进 `startPositionMs`）。一旦这两处判定不一致，  
就会出现"记录里是第 8 分钟、播放器却从第 3 分钟开始"这类极难排查的漂移。

**切集 / 换线路复用同一个内核**（先 `stop()` 再 `open()`）：  
重建内核会有 300ms 级黑屏，做不到"无缝切换"。  
换线路时会**尽最大努力保留观看位置** —— 若新线路上存在同一序号的集，  
且记录的正是这一集，则续着看，而不是把用户退回片头。

**集序号 ≠ 列表下标**：观看记录里存的、UI 展示的、聚合层对齐的统统是  
`Episode.index`（集序号），而源站可能缺集或倒序。因此定位一律走  
`PlaySource.episodeByIndex()`，不能用 `episodeAt()`（后者是列表下标）。

### 6.7 播放控制层（Controls Overlay）

需求明确要求：**无论全局是否浅色模式，播放层内部必须半透明暗色**。  
这不是审美偏好而是可读性刚需 —— 视频亮度不可控，浅色控件落在高光雪景  
镜头会彻底消失。因此有独立于主题的 `PlayerPalette`：

```text
浅色主题                播放层
canvas  #F5F6F8   ←→    videoBackground #000000
surface #FFFFFF   ←→    panel           #14161A
ink     #1F2329   ←→    ink             #FFFFFF
accent  #E8543F   ←→    accent          #FF6B55（暗底提亮）
```

遮罩用**渐变而非实色**：顶部 70% 黑 → 透明、底部 80% 黑 → 透明。  
整块不透明黑条会把"在看视频"变成"在看字幕条"，失去沉浸感。

| 要求             | 实现                                                                    |
| -------------- | --------------------------------------------------------------------- |
| 播放 / 暂停        | 中央 64px 大按钮 + 左右 10 秒快退/快进按钮                                          |
| 手势拖动进度条        | `PlayerProgressBar`：三段式轨道（缓冲 / 已播 / 轨道）+ 拖动时间气泡                       |
| 双击快进 / 快退 10 秒 | 左 40% 快退、右 40% 快进、中间 20% 不动作（避免误触）                                    |
| 倍速菜单           | 0.5x / 1.0x / 1.25x / 1.5x / 2.0x，锚定弹出菜单，当前档位打勾                       |
| 选集抽屉           | 右侧滑入；倒序开关；**当前集自动滚进视野**                                               |
| 线路切换抽屉         | 每条线路给出集数 / 可播数 / 直链率 / 切过去对应第几集                                       |
| 全屏 / 最大化       | 桌面端 `window_manager.setFullScreen`；移动端锁横屏 + 沉浸式                       |
| 移动端旋转与锁横屏      | 进入播放页即 `setPreferredOrientations(landscape)` + `immersiveSticky`，退出还原 |
| 弱网一键换源 / 重试    | 缓冲超过 8 秒才浮出（正常起播、切分片都会短暂缓冲，不该视为异常）                                    |
| 失败浮层           | 按失败分类决定主按钮，附"技术细节"折叠区与"复制错误信息"                                        |

**手势冲突的处理**：Flutter 原生的 `onTap` + `onDoubleTap` 组合会让单击  
**必须等 300ms** 才能确认，界面上表现为"点了没反应"。这里自己实现判定：  
单击立刻生效，220ms 内出现第二次点击则撤销显隐、改判为双击 seek。

**控制层自动隐藏**做了节流：鼠标悬停回调可达 60Hz，  
每秒重建 60 个 `Timer` 毫无意义；只要计时器还在跑就跳过重置，  
最坏让控制层多显示 250ms，用户完全无感。

### 6.8 Provider 与内核 API 一览

| 名称                            | 作用                                                      |
| ----------------------------- | ------------------------------------------------------- |
| `playerConfigProvider`        | 全局播放策略（重试 / 超时 / 硬解 / 缓冲），可 override                    |
| `playerEngineFactoryProvider` | 内核工厂。做成工厂而非单例：重量级资源，生命周期与播放页对齐；测试可注入 `FakePlayerEngine` |
| `sourceConfigByKeyProvider`   | 按 key 查数据源配置 —— 播放层推导防盗链请求头的唯一来源                        |

`PlayerEngineConfig` 关键参数：`maxRetryAttempts=3`、`retryBaseDelay=800ms`、  
`openTimeout=25s`、`stallTimeout=20s`、`hardwareAcceleration=true`、  
`networkTimeoutSec=20`、`demuxerMaxBytes=64MiB`。

`PlayerEngine` 公开方法：`open` / `play` / `pause` / `togglePlay` /  
`seek` / `seekBy` / `setRate` / `setVolume` / `retry` / `stop` /  
`buildVideo` / `dispose`。

### 6.9 本阶段的关键取舍

| 取舍                | 选择                            | 理由                         |
| ----------------- | ----------------------------- | -------------------------- |
| 播放动作              | 内嵌播放页                         | 外部播放器无法回传位置，进度回写永远是"起播点"   |
| 内核实例              | 每播放页一个                        | 重量级原生资源；为画中画留出多实例空间        |
| `startPositionMs` | 拿到时长后再 Seek                   | `open` 完成前的 Seek 会被内核丢弃    |
| 进度监听              | `ValueListenable`，不进 Riverpod | 10Hz 全局 state 会让整棵树按帧重建    |
| 失败 UI             | 按分类决定主按钮                      | 三个按钮平铺会让用户逐个试，反而更慢         |
| 断流检测              | 看门狗计时器                        | 弱网最典型的形态是"不报错也不推进"         |
| 缓冲提示              | 8 秒后才浮出                       | 瞬时缓冲是正常现象，立刻提示是噪声          |
| 画面点击              | 自研 220ms 双击窗口                 | 原生组合会让单击等 300ms，手感迟钝       |
| 续播浮层              | 移入播放页（暗色）                     | 只有内核知道何时能真正 Seek；浅色弹窗打断沉浸感 |

**本阶段删除的东西**（均为被新架构取代的死代码）：

- `presentation/widgets/resume_prompt.dart` —— 浅色续播弹窗，  
  判定逻辑（`ResumeChoice` / `shouldPromptResume`）迁入 `resume_overlay.dart`；
- `url_launcher` 依赖 —— 外部播放器路径已被内嵌播放取代，不再有调用点；
- `PlaybackStatus.isActive` / `isTerminal`、`PlaybackState.aspectRatio` /  
  `remainingLabel`、`MediaKind.isStreaming` —— 定义但无消费方。

---

## 7. 阶段五：打包与发布

完整分步操作（含 iOS 侧载全流程与故障排查表）见  
**[`docs/BUILD_AND_RELEASE.md`](docs/BUILD_AND_RELEASE.md)**，本节只讲设计决策。

### 7.1 为什么要「云端构建 + 未签名」

构建 iOS 产物必须 macOS + Xcode，Windows 上无解 → 交给 GitHub Actions。

而在 CI 里做**正式签名**需要把 Apple 分发证书（`.p12`）和描述文件塞进 Secrets。  
对自用/自签场景这是纯粹的负担，证书泄漏的后果还很严重。所以工作流只产出  
**未签名 `.ipa`**，签名留到设备侧用 TrollStore / AltStore / Sideloadly 完成——  
完全免费、零证书管理。

### 7.2 三个时效性陷阱（都是照着老教程做会踩的）

| 陷阱                            | 事实                                                                             | 后果                                                                                                 |
| ----------------------------- | ------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------- |
| **`macos-14` runner**         | GitHub 公告：macos-14 自 **2026-07-06** 起弃用，**2026-11-02** 起完全停止支持                 | 工作流某天直接排队失败（no matching runner），失败信息和代码毫无关系。**改用 `macos-15`**                                      |
| **Flutter 3.22.x + Xcode 16** | `macos-15` 默认 Xcode 16，其新的 module verifier 不被 Flutter < 3.24.4 的 iOS 工具链认识     | 编译期报 `No such module 'Flutter'` / `ModuleCache.noindex/Session.modulevalidation` 缺失。**默认用 3.24.5** |
| **iOS 最低版本 13.0**             | media_kit 在 iOS 上打包的是 **MPVKit**（libmpv 的 Apple 构建），podspec 要求 13.0；脚手架默认 12.0 | 只改 Podfile 或只改 pbxproj 都不行，`pod install` 报 "could not find compatible versions"                    |

`pubspec.yaml` 声明的是 `flutter: '>=3.22.0'`（下限），所以用 3.24.5 完全兼容。

> 顺带纠正第四阶段的一处描述错误：media_kit 在 **iOS 上也是 libmpv**，  
> 不是 AVPlayer / AVFoundation 后端。这不是细节——它直接决定了  
> 「最低版本 13.0」和「拿不到系统级画中画（PiP 只能挂 AVPlayerLayer）」两件事。

### 7.3 iOS 工程配置补全

`tool/patch_ios_project.py` 幂等地补齐（合并而非覆盖，可重复执行）：

| 键 / 设置                                                         | 值             | 不配的后果                                                                                        |
| -------------------------------------------------------------- | ------------- | -------------------------------------------------------------------------------------------- |
| `NSAppTransportSecurity.NSAllowsArbitraryLoads`                | `true`        | 大量源站的 `http://` 直链被 ATS 静默拦截，UI 上只显示「播放失败」                                                   |
| `UIBackgroundModes`                                            | `[audio]`     | 切后台即断音。**刻意不加 `picture-in-picture`**：libmpv 是自绘纹理，拿不到 PiP，声明了反而误导                            |
| `UISupportedInterfaceOrientations`（+ `~ipad`）                  | 含两个 landscape | **`SystemChrome.setPreferredOrientations` 只能在 Info.plist 声明的全集内收窄**。缺 landscape 时播放页锁横屏会静默失效 |
| `UIRequiresFullScreen`                                         | `true`        | iPad 分屏模式下系统忽略方向锁定、窗口可任意缩放，播放器画布不稳定                                                          |
| `UIViewControllerBasedStatusBarAppearance`                     | `false`       | 播放页 `immersiveSticky` 隐藏状态栏失效                                                                |
| `CADisableMinimumFrameDurationOnPhone`                         | `true`        | ProMotion 机型帧率被压在 60Hz                                                                       |
| `ITSAppUsesNonExemptEncryption`                                | `false`       | 每次上传 App Store 都要回答出口合规问询                                                                    |
| Podfile `platform :ios` + pbxproj `IPHONEOS_DEPLOYMENT_TARGET` | `13.0`        | 见 §7.2 第三行                                                                                   |

**为什么屏幕方向要写成「四个方向全集」**：Info.plist 是「允许出现的全集」，  
Dart 侧是「运行时收窄」。播放页锁横屏能生效的前提，正是这里已经声明了 landscape。

### 7.4 未签名 IPA 的构建与封装

工作流（`.github/workflows/build-ios.yml`）的关键几步：

1. `flutter build ios --release --no-codesign` → `build/ios/iphoneos/Runner.app`
2. `ditto Runner.app Payload/Runner.app` 组装标准 IPA 结构
3. **符号链接守卫**：比对源与副本的链接数，不一致就报错
4. `zip -r -y -q -X` 压缩成 `movie_hub_unsigned.ipa`
5. 结构自检 + 归档侧再确认链接存活
6. 上传 Artifact；tag 推送时自动发 Release

**为什么第 3、4 步要看这么细**：`Runner.app` 内的 framework 含  
`Versions/Current`、`Headers` 这类符号链接。一旦被解引用成实体副本，  
产出的 IPA 结构就不合法——表现为**装机时提示「无法安装」或装完闪退**，  
而且报错完全指不到打包这一步。所以这里把「链接必须存活」从隐式不变量  
变成了显式断言。

`cp -R` 在 macOS 上其实也会保留链接，但它的行为依赖「源路径带不带结尾斜杠」  
这种隐式语义（多写一个 `/` 就变成 `Payload/Runner.app/Runner.app`，直接不合法）。  
`ditto` 是 Apple 专为 bundle 设计的复制工具，目标路径含义明确。

### 7.5 Windows 的两种分发形态

Flutter 的 Windows Release 产物**本质是一个目录**（exe + 引擎 dll + `data/` 资源），  
没有官方的单文件输出。因此：

| 形态     | 做法                                         | 适合                |
| ------ | ------------------------------------------ | ----------------- |
| 免安装便携版 | 整目录压 zip，解压即用                              | 自用 / 拷给朋友 / 放 U 盘 |
| 正规安装包  | Inno Setup（`tool/installer/movie_hub.iss`） | 需要开始菜单、卸载项        |

**目标机的硬性依赖**：Microsoft Visual C++ 2015-2022 Redistributable (x64)。  
Flutter 模板默认动态链接 CRT（`/MD`），缺了它的表现是**双击没反应**——  
没有对话框、日志里也难找。所以：

- 便携版目录里附一份「使用说明.txt」，把这件事写在最前面；
- 安装包的 `[Code]` 段在安装前查注册表并提示  
  （用注册表而不是找 `vcruntime140.dll`：安装程序是 32 位进程，访问 `System32`  
  会被 WOW64 重定向到 `SysWOW64`，在那里找 64 位运行库必然找不到）。

`tool/package_windows.ps1` 还会做**产物完整性校验**：缺 `libmpv*.dll` 直接报错。  
少了它，应用能启动、能浏览，但一点播放就崩。

### 7.6 iOS 侧载：先查系统版本再选工具

TrollStore 靠 iOS 的 CoreTrust 漏洞实现**永久签名**，但 Apple 从 **iOS 17.0.1**  
起修掉了它——这是硬件 + 系统版本决定的一次性机会，不存在「以后会支持」。

| 方式         | 有效期      | 适用系统                                    |
| ---------- | -------- | --------------------------------------- |
| TrollStore | **永久**   | iOS 14.0–16.6.1、16.7 RC、17.0（A12+ 体验最好） |
| AltStore   | 7 天自动续签  | 系统太新用不了 TrollStore；需电脑常驻 AltServer      |
| Sideloadly | 7 天手动重签  | 偶尔装一次                                   |
| SideStore  | 7 天设备内续签 | 首次配对后不再需要电脑                             |

iOS 17.0.1 及以上、18+ / 26 **均不支持 TrollStore**，只能走 7 天签名路线。

> 关于 entitlements：TrollStore 用 `ldid` 重签并**原样保留**你给的 entitlements。  
> 有三类在 iOS 15 / A12+ 上被禁用，带上会**启动即崩溃**：  
> `com.apple.private.cs.debugger`、`dynamic-codesigning`、  
> `com.apple.private.skip-library-validation`。  
> 本工程产出的是 `--no-codesign` 的干净 IPA，不含任何 entitlements，天然规避。

### 7.7 本阶段的关键取舍

| 取舍                        | 决定                                      | 理由                                                              |
| ------------------------- | --------------------------------------- | --------------------------------------------------------------- |
| runner 标签                 | `macos-15` 固定，**不用** `macos-latest`     | `-latest` 会随 GitHub 迁移计划漂移，在你不改代码时换掉 Xcode，属于不可控变量              |
| 签名                        | 云端**不签名**                               | 零证书管理；自签工具会重签，CI 里签没有收益只有风险                                     |
| `push` 是否加 `paths-ignore` | **不加**                                  | 打 tag 时若「相对上次提交只改了文档」会被静默跳过，Release 里没产物却看不出原因。这种静默跳过比多花几分钟昂贵得多 |
| IPA 内嵌签名                  | 保留，仅在需要时通过 `strip-signatures` 剥离        | 默认不动；只有侧载工具报「签名无效」时才剥——用参数显式开关比无条件剥离更可控                         |
| PiP                       | Info.plist **不声明** `picture-in-picture` | libmpv 自绘纹理拿不到 PiP，声明了是自我欺骗。要做 PiP 需换 iOS 侧内核，属独立技术路线           |
| 便携版形态                     | 目录 zip，不做单文件                            | 真单文件需 MSIX / SFX，对自用场景是纯复杂度                                     |
| iOS 工程配置                  | 脚本化（Python）而非文档化                        | 文档会漏、会过期；脚本幂等、可重复执行，且云端工作流也跑一遍，本地忘了也不影响产物                       |

---

## 8. 运行与打包

### 8.1 首次运行（新克隆的仓库）

```powershell
flutter pub get

# ① 补平台目录（本仓库不预置 ios/ windows/）
powershell -ExecutionPolicy Bypass -File tool/scaffold_platforms.ps1

# ② 补 iOS 工程配置（ATS / 后台音频 / 旋转 / 最低版本 13.0）
python tool/patch_ios_project.py --print

flutter analyze
flutter run -d windows      # Windows 桌面端
```

`flutter run -d ios` 需要 macOS + Xcode，Windows 上不可用 —— 这正是  
第五阶段引入 GitHub Actions 云端构建的原因。

无需 `build_runner`：本地持久化用 Hive 但**手写 TypeAdapter**，  
仓库内不存在 `.g.dart` 生成物（详见 §5.2）。

### 8.2 打包

```powershell
# Windows 便携版 zip
powershell -ExecutionPolicy Bypass -File tool/package_windows.ps1

# Windows 便携版 + Inno Setup 安装包（需先装 Inno Setup 6）
powershell -ExecutionPolicy Bypass -File tool/package_windows.ps1 -Clean -Installer
```

iOS 包走云端：

```powershell
git push origin main            # 自动构建，产物在 Actions → Artifacts
git tag v1.0.0; git push origin v1.0.0   # 自动发布 GitHub Release
```

完整流程、参数说明与故障排查见 **[`docs/BUILD_AND_RELEASE.md`](docs/BUILD_AND_RELEASE.md)**。

### 8.3 平台注意事项

| 平台      | 说明                                                                                                                                                                                                                     |
| ------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Windows | 需启用开发者模式（`window_manager` 依赖）；窗口 1280×820，最小 960×640；`media_kit` 使用 libmpv。**编译需 VS 2022「使用 C++ 的桌面开发」工作负载；便携版运行需 VC++ 2015-2022 Redistributable (x64)**                                                               |
| iOS     | `http` 明文地址必须在 `Info.plist` 配置 ATS 例外；`SafeArea` 已适配灵动岛与 Home 指示条；**最低系统版本 13.0（Podfile 与 pbxproj 要同时改）**                                                                                                              |
| 播放内核    | Windows / iOS **都是 libmpv**（iOS 上是 MPVKit，不是 AVPlayer）。首次启动会加载原生库（Windows: `libmpv-2.dll` 全家桶），`PlayerBootstrap.ensureInitialized()` 已在 `main()` 中早于 `runApp()` 执行；播放页持 `WakelockPlus` 防息屏。**系统级画中画（PiP）不可用**，原因见 §7.2 |
| 网络层     | 部分源站返回 GBK，`HttpService.decodeBody` 已留升级位（引入 `fast_gbk` 后两行接入）                                                                                                                                                         |
| 主题      | 仅浅色模式（`themeMode: ThemeMode.light`）；系统字号缩放钳制在 0.9~1.25，防止布局崩坏。播放层例外：内部强制半透明暗色覆盖层（`PlayerPalette`），与全局主题无关                                                                                                              |
| 本地存储    | Hive Box 落在应用文档目录（Windows）/ 沙盒 Documents（iOS），均在应用私有空间内，无需额外权限声明                                                                                                                                                       |

### 首次使用

客户端不内置任何站点。启动后进入「数据源」页 → 导入订阅。  
可参考 `assets/sample/subscription.example.json` 的字段语义  
（示例域名为占位，需替换为你自行维护的源站）。

观看记录为**纯本地数据**：没有任何账号体系与网络请求，  
断网、甚至全部数据源失效时，「我的片库」依然可以正常浏览与续播定位。

### 开发工具：结构静态校验

本仓库自带一个**无需 Flutter 工具链**的结构校验脚本，可在编辑后秒级自检：

```bash
python tool/verify_structure.py
```

它覆盖 7 项检查（退出码 0/1，可直接接 CI 前置步骤）：

| 检查 | 内容                                            |
| -- | --------------------------------------------- |
| A  | 全部相对 `import`/`export` 路径能否解析到真实文件            |
| B  | 未使用的相对 `import`（穿透 barrel 文件的 re-export 正确判定） |
| C  | 设计令牌成员引用（如 `AppColors.ink`）是否存在               |
| D  | Provider 标识符是否均有定义                            |
| E  | 构造调用实参是否与形参表匹配（支持 `{命名}` / `[可选位置]` 混排）       |
| F  | 命名构造函数与关键工具类的成员引用是否存在                         |
| G  | 死代码：定义了但全项目从未引用的公开类型                          |

> 局限：它不解析类型系统（泛型、可空性、重载），因此**不能替代 `flutter analyze`**，  
> 只作为快速的结构一致性护栏。

---

## 9. 范围与后续

**第一阶段（已完成）**

- 分层目录与依赖方向约束
- 数据源订阅协议 v1 + 协议文档
- `MovieModel` / `PlaySource` / `Episode` 完整模型
- 声明式解析层（苹果CMS + 通用 JSON + 结构化选集）
- 多源并发搜索、相关性过滤、两轮去重聚合
- 数据源管理：导入 / 校验 / 合并 / 热更新 / 异常捕获

**第二阶段（已完成）**

- 浅色极简设计令牌体系（`core/design/`，7 文件）
- `app_theme.dart` 浅色 ThemeData（全部组件主题归一）
- 设计系统组件（脚手架 / 毛玻璃 / 骨架屏 / 卡片 / 网格 / 轮播 / 胶囊 / 菜单 / 三态按钮 / 确认弹窗）
- 响应式脚手架：桌面悬浮侧边栏 ↔ 移动悬浮底部栏，含 `AppScaffoldInsets`
- 4 个核心页面：首页发现 / 聚合搜索（流式）/ 片库 / 影视详情
- 首页 Feed 装配服务（分区定义 + 降级链 + 分批加载）

**第三阶段（已完成）**

- Hive 持久化层（手写 `TypeAdapter`，免 `build_runner`）+ 旧 `shared_preferences` 数据迁移
- `WatchRecord` 实体 + 三态状态机（想看 / 正在看 / 已看）+ 聚合状态 `WatchHistoryState`
- `WatchHistoryRepository`（薄仓储 + 500 条容量治理）与 `WatchHistoryNotifier`
- 进度回写：5 秒心跳 + 脏标记 + 最小变化量跳过 + `flush(force:)` 兜底
- 断点续播：`getLastWatchRecord` + 续播询问 + 「从头播放」语义
- 资料库页三分栏 Tab、进度卡片、点击续播、滑动 / 右键快捷操作
- 详情页三态按钮（`WatchStatusButton`）与状态变更失败回滚提示（`runWatchAction`）
- 首页「继续观看」与侧边栏角标接入新 Provider

**第四阶段（已完成）**

- 播放内核抽象 `PlayerEngine` + media_kit(libmpv) 实现 `MediaKitPlayerEngine`
- `PlayerBootstrap` 全局初始化生命周期（`main()` 中早于 `runApp`）
- 媒体类型识别（HLS / DASH / MP4 / MKV / FLV / TS），`?` 前路径优先的判定顺序
- 防盗链请求头注入（UA / Referer / Origin / Cookie，五级优先级）
- 失败分类（8 类）+ 断流看门狗 + 指数退避自动重试 + 解码失败降级软解
- 单一状态机（7 态）与不可变状态快照 `PlaybackState`（含值相等）
- 播放控制层：半透明暗色覆盖层、三段式进度条、双击 ±10s、倍速菜单、  
  选集 / 线路侧滑抽屉、全屏切换、移动端锁横屏、弱网一键换源、锁屏防误触
- 播放页闭环：`beginSession` → `reportPosition` 心跳 → `flush` / `endSession`，  
  ≥90% 自动转「已看」；续播浮层一键 Seek

**第五阶段（已完成）**

- `tool/scaffold_platforms.ps1`：生成 `ios/` `windows/` 平台脚手架（本仓库是「先写业务码、后补平台目录」的形态）
- `tool/patch_ios_project.py`：幂等补齐 iOS 工程配置  
  （ATS 明文放行 / 后台音频 / 屏幕方向全集 / iPad 全屏 / 状态栏接管 / 120Hz /  
  加密合规，以及 Podfile 与 pbxproj 的最低版本 13.0）
- `.github/workflows/build-ios.yml`：`macos-15` + Flutter 3.24.5 + CocoaPods 缓存，  
  出**未签名** `.ipa`；含符号链接守卫、IPA 结构自检、Artifact 上传、  
  tag 推送自动发 GitHub Release；`strip-signatures` 按需剥离内嵌签名
- `tool/package_windows.ps1`：一键出 Windows 便携版 zip（含产物完整性校验、  
  自动附带「使用说明.txt」说明 VC++ 运行库依赖），`-Installer` 走 Inno Setup 出安装包
- `tool/installer/movie_hub.iss`：Inno Setup 6 脚本（UTF-8 BOM + 中文界面 +  
  安装前查注册表检测 VC++ 运行库）
- `docs/BUILD_AND_RELEASE.md`：Git 推送 → 云端构建 → 下载 Artifact →  
  TrollStore / AltStore / Sideloadly / SideStore 侧载的全流程与故障排查表

**后续阶段**

- 线路测速与自动择优（`PlaySource.qualityScore` 已有基础，待接入实测带宽）
- 弹幕（需第三方弹幕库匹配）
- 投屏（DLNA / AirPlay）与画中画（PiP 需换 iOS 侧内核，见 `docs/BUILD_AND_RELEASE.md`)
- 播放页批量下载（离线缓存）

---

## 10. 合规声明

本项目仅实现**通用数据源的声明式描述与解析框架**，不内置、不附带任何  
第三方站点的采集逻辑或影视内容。

- 客户端**不内置任何影视站点、不内置任何爬虫代码、不提供任何内容源**；
- 数据源完全由用户以声明式 JSON 订阅导入，客户端只做协议解释、聚合与播放；
- 播放内核（`media_kit` / libmpv）仅为通用多媒体解码组件，不含任何站点适配逻辑。

使用者应自行确保所配置数据源的合法性，遵守相应站点服务条款及所在地区的法律法规。
