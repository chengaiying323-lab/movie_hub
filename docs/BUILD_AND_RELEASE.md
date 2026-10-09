# MovieHub · 打包与发布指南

> **核心前提：本地不装任何东西也能出全平台安装包。**
> 平台脚手架生成、iOS 工程补丁、iOS 编译、Windows 编译全部在 GitHub Actions 上完成。
> 你本地只需要能 `git push`。

---

## 0. 速览

### 零本地环境路线（推荐）

| 步骤 | 在哪做 | 说明 |
|---|---|---|
| ① 把源码推上 GitHub | 本地（只需 Git） | 见 [§4.2](#42-最小推送流程零本地环境) |
| ② 等 Actions 跑完 | 云端 | 自动生成平台目录 + 打补丁 + 编译 |
| ③ 下载 Windows 包 | 浏览器 | Actions → Artifacts → `movie_hub-windows-x64-*.zip` |
| ④ 下载 iOS 包 | 浏览器 | Actions → Artifacts → `movie_hub-ios-unsigned-*.zip`（**内含 `.ipa`，要解压**） |
| ⑤ 装到 iPhone | 设备侧 | [§5](#5-ios-安装未签名-ipa-怎么装上去) |

GitHub **公开仓库**的 macOS / Windows runner 免费；私有仓库会消耗付费额度。

### 有一个完整本地环境时（可选）

| 目标 | 命令 | 产物 |
|---|---|---|
| 生成平台目录 | `tool/scaffold_platforms.ps1` | `ios/`、`windows/` |
| 修好 iOS 工程配置 | `python tool/patch_ios_project.py` | Info.plist / Podfile（**缺失时自动生成**）/ pbxproj 就绪 |
| 本地出 Windows 包 | `tool/package_windows.ps1` | `dist/*-portable.zip`（+ `-Installer` 出安装包） |

本地做这些的**唯一好处**是省一次 CI 往返；产物和云端构建完全一致（走的是同一套脚本）。

---

## 1. 平台目录与 iOS 配置：现在由云端自动完成

### 1.1 为什么需要这一步

本仓库是「先写业务代码、后补平台目录」的形态——`lib/` 已完整，但 `ios/`、`windows/`
**没有**生成（Flutter 不会自动补）。

**你不需要为这件事做任何操作。** 两个工作流都会在处理前按需生成：

```bash
# build-ios.yml / build-windows.yml 里的逻辑（简化）
if [ 平台目录已存在 ]; then
  跳过
else
  flutter create --platforms=<ios|windows> --project-name movie_hub <临时目录>
  cp -R <临时目录>/<platform>/. <platform>/
fi
```

### 1.2 为什么在临时目录生成，而不是在仓库里跑 `flutter create .`

`flutter create .` 虽然默认不覆盖已存在的文件（`--overwrite` 默认为 false），
但它确实会**补写**缺失的模板文件（`analysis_options.yaml`、`.gitignore`、`.metadata` 等），
而且这个行为随 Flutter 版本变动 —— 副作用不可控。

「临时目录生成 → 只把平台目录拷回来」有两个好处：

- **对仓库零副作用**：绝不触碰 `README.md` / `.gitignore` / `lib/` / `pubspec.yaml`
- **意图明确**：我们需要的只是平台目录，拷贝范围就等于需求范围

（这条逻辑已用模拟 `flutter create` 产物的夹具实测通过：平台目录含隐藏文件一并拷入，
仓库内 4 个文件全部未被改动。）

### 1.3 iOS 工程补丁同样在云端跑（含补出 Podfile）

`flutter create` 生成的 iOS 工程**开箱不可用**，而且少一个关键文件：

| 问题 | 后果 |
|---|---|
| **`ios/Podfile` 压根不存在** —— `flutter create` 不生成它（Flutter 已把模板挪到 `templates/cocoapods/Podfile-ios`，只在跑 CocoaPods 时才按需投放） | `pod install` 直接失败 |
| 最低版本是 12.0，而 media_kit 的 MPVKit 要求 13.0 | `pod install` 报 `could not find compatible versions` |
| ATS 没放行明文 HTTP | 大量 `http://` 视频直链被静默拦截，UI 上只显示「播放失败」 |
| 缺横屏声明 | 播放页锁横屏**静默失效**（不报错，就是不转） |

工作流在每个构建里都会跑 `python3 tool/patch_ios_project.py`，
**Podfile 缺失时会现场生成一份标准模板**（优先取当前 Flutter SDK 自带的
`Podfile-ios`，取不到才用脚本内置副本），并把它改造成：

```ruby
platform :ios, '13.0'          # 决定 CocoaPods 的依赖解析版本

post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)   # ← 它会把目标拉回 Flutter 默认值
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '13.0'   # ← 必须写在它之后
    end
  end
end
```

所以**即使你从不碰 iOS 目录，产物也是配置正确的**。各项的详细原因见 [§2](#2-ios-工程配置补了哪些键为什么)。

> 这一步刻意**不做** `test -f ios/Podfile` 之类的存在性断言：
> 脚本自身出错会以非零退出码让步骤失败，断言是重复的；而多一层硬断言只会在
> 「Podfile 由谁生成」这件事变化时制造假失败，把整条构建卡在一个本可自动修复的问题上。
> 状态改由 `--print` 打印出来（可见但不阻断）。

### 1.4 想换成自己的 Bundle ID

改 `.github/workflows/build-ios.yml` 顶部的：

```yaml
env:
  IOS_ORG: com.moviehub     # → com.你的域名
```

生成的 Bundle ID 是 `${IOS_ORG}.movieHub`。

---

## 2. iOS 工程配置：补了哪些键、为什么

`flutter create` 生成的 Info.plist 是**通用模板**，对「视频聚合播放器」这个具体场景
缺了三类东西。下面每一项都说明「不配会怎样」，便于你判断遇到问题时该查哪里。

### 2.1 ATS —— 放行明文 HTTP

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key><true/>
    <key>NSAllowsArbitraryLoadsInWebContent</key><true/>
    <key>NSAllowsLocalNetworking</key><true/>
</dict>
```

**不配的后果**：iOS 默认拦截所有 `http://` 请求，而大量影视源站的视频直链是明文 HTTP。
更麻烦的是错误很隐晦——`NSURLErrorAppTransportSecurityRequiresSecureConnection`
往往被底层媒体库吞掉，UI 上只剩一句「播放失败」，根本看不出是系统策略拦的。

**取舍说明**：`NSAllowsArbitraryLoads` 是「全部放开」，攻击面最大。如果将来只接 HTTPS 源，
应该把它改回 `false`，改用按域名白名单：

```xml
<key>NSExceptionDomains</key>
<dict>
    <key>your-source-domain.com</key>
    <dict>
        <key>NSExceptionAllowsInsecureHTTPLoads</key><true/>
    </dict>
</dict>
```

### 2.2 后台模式（UIBackgroundModes）与**能力边界**

```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

**只声明 `audio`，刻意不声明 `picture-in-picture`。** 这不是偷懒，是事实限制：

> media_kit 在 iOS 上走的是 **libmpv（MPVKit）**，自绘纹理输出，
> **不是 AVPlayer/AVFoundation**。而系统级画中画（PiP）只能挂载在 `AVPlayerLayer` 上。
> 声明了 `picture-in-picture` 也拿不到 PiP 能力，反而会让后续开发误以为「已经支持了」。

**当前能力**：切到后台后音频继续播放（`audio` 模式 + AVAudioSession 生效）。

**想真正做 PiP 需要**：
1. 换掉 iOS 侧播放内核（改用 `video_player` / 原生 AVPlayer）；
2. 用 `AVPictureInPictureController` 包一层；
3. 在 Info.plist 加上 `<string>picture-in-picture</string>`。

这是一条独立的技术路线，不属于本次打包范围。

### 2.3 屏幕旋转

```xml
<key>UISupportedInterfaceOrientations</key>
<array>
    <string>UIInterfaceOrientationPortrait</string>
    <string>UIInterfaceOrientationLandscapeLeft</string>
    <string>UIInterfaceOrientationLandscapeRight</string>
</array>
<key>UISupportedInterfaceOrientations~ipad</key>
<array>
    <string>UIInterfaceOrientationPortrait</string>
    <string>UIInterfaceOrientationLandscapeLeft</string>
    <string>UIInterfaceOrientationLandscapeRight</string>
    <string>UIInterfaceOrientationPortraitUpsideDown</string>
</array>
```

**这里有个最容易踩的坑，务必理解：**

> Info.plist 声明的是「应用**允许**出现的方向全集」。
> Dart 侧的 `SystemChrome.setPreferredOrientations` 只能在这个全集**之内**收窄，
> **不能超出**。

所以第四阶段播放页里那句「锁横屏」——`setPreferredOrientations([landscapeLeft, landscapeRight])`
——之所以能生效，前提正是 Info.plist 里**已经有 landscape**。

`flutter create` 生成的模板对 iPhone 通常已含横屏，但如果你手工改过、或者只想要竖屏应用，
播放页的锁定会**静默失效**（不报错，就是不转）。脚本用「取并集」而不是「覆盖」的方式来
保证四个方向齐备，同时不抹掉你已有的自定义顺序。

**iPad 额外说明**：`UIRequiresFullScreen = true` 是必需的。iPad 默认支持分屏多任务，
那种模式下系统会忽略方向锁定、窗口还能被任意拖拽缩放——播放器需要一个稳定的横屏画布。
代价是应用不再出现在 iPad 分屏列表里，对视频播放器是合理取舍。

### 2.4 其余键

| 键 | 值 | 为什么 |
|---|---|---|
| `UIViewControllerBasedStatusBarAppearance` | `false` | 播放页用 `setEnabledSystemUIMode(immersiveSticky)` 隐藏状态栏。iOS 上要由 Flutter 接管状态栏显隐，这个键必须为 false，否则系统说了算，沉浸式失效 |
| `CADisableMinimumFrameDurationOnPhone` | `true` | ProMotion 机型默认把 Flutter 自绘帧率压在 60Hz。打开后动画/滚动才真正跑到 120Hz |
| `UIApplicationSupportsIndirectInputEvents` | `true` | 触控板/鼠标的间接输入事件（桌面级指针语义） |
| `ITSAppUsesNonExemptEncryption` | `false` | 本应用只用系统 HTTPS/标准库密码学，无「非豁免加密」。显式声明可跳过 App Store 每次上传的出口合规问询 |

### 2.5 最低系统版本 13.0 —— **三处必须同时到位**

这是本项目 iOS 构建最常见的失败原因：

| 位置 | 字段 | 作用 |
|---|---|---|
| `ios/Podfile` 顶部 | `platform :ios, '13.0'` | 决定 CocoaPods 的**依赖解析**版本 |
| `ios/Podfile` 的 `post_install` | `config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '13.0'` | 决定每个 Pod 目标**实际编译**的版本。必须写在 `flutter_additional_ios_build_settings(target)` **之后**，否则会被它拉回 Flutter 默认值（3.24 线是 12.0） |
| `ios/Runner.xcodeproj/project.pbxproj` | `IPHONEOS_DEPLOYMENT_TARGET = 13.0` | 决定宿主 App **实际编译**的版本 |

**为什么必须是 13.0**：media_kit 在 iOS 上打包的是 MPVKit（libmpv 的 Apple 平台构建），
其 podspec 声明 `platform :ios, '13.0'`。而 Flutter 脚手架默认写 12.0。

**只改一处仍然会失败**，而且报错信息指向的是 pod 而不是你改的那个文件，很容易查错方向：

```
[!] CocoaPods could not find compatible versions for pod "media_kit_libs_ios_video"
```

> 顺带一提：`project.pbxproj` 里这个键在 Debug / Profile / Release **三套 build
> configuration 里各有一份**，所以脚本会报「共 3 处」而不是「1 处」。
> 看到 3 才说明改全了。
>
> 另外 `ios/Podfile` **并不由 `flutter create` 生成**（这点很反直觉，见 [§1.3](#13-ios-工程补丁同样在云端跑含补出-podfile)）。
> 脚本在它缺失时会用 Flutter SDK 自带的官方模板现场补一份，再打上上面的两处 13.0。

### 2.6 不想用脚本？手工对照

`patch_ios_project.py` 做四件事，手工做也可以：

1. **Info.plist**：把 [§2.1](#21-ats--放行明文-http) ~ [§2.4](#24-其余键) 的 XML 片段插进
   顶层 `<dict>` 里（用 Xcode 的 plist 编辑器，或直接改 XML）。
2. **Podfile**：若 `ios/Podfile` 不存在，先跑一次 `flutter build ios`（或
   `cd ios && pod install`）让 Flutter 工具投放模板；然后把 `# platform :ios, '12.0'`
   这行的注释去掉并改成 `13.0`。
3. **Podfile 的 post_install**：在 `flutter_additional_ios_build_settings(target)`
   之后追加 `target.build_configurations.each { ... IPHONEOS_DEPLOYMENT_TARGET = '13.0' }`。
4. **pbxproj**：在 Xcode 里选中 `Runner` target → Build Settings → 搜
   `iOS Deployment Target` → 改成 `13.0`（三处 configuration 都要）。

用脚本的好处是**幂等**、**会自动补出缺失的 Podfile**、且**不会漏掉那三处 configuration**。

### 2.7 iOS 编不过：`volume_controller` 的版本陷阱

**症状**（出现在 Xcode 编译阶段，不是 `pod install` 阶段）：

```
Swift Compiler Error (Xcode): Cannot find type 'FlutterSceneLifecycleDelegate' in scope
```

报错文件通常在 `volume_controller-x.y.z` 里。

**根因**：`volume_controller` **不是**本项目的直接依赖，而是 `media_kit_video`
拖进来的**传递依赖**：

```
media_kit_video ^1.2.4  →  1.3.1  →  volume_controller ^3.0.2  →  3.4.4
```

从 **3.4.2** 起 `volume_controller` 开始使用 iOS 的 **UIScene 生命周期协议**
（`FlutterSceneLifecycleDelegate`），而 CI 用的 Flutter 3.24.5 还没有这个协议。

**为什么 pub 不自动避开**：`volume_controller` 3.4.2–3.4.4 在 pubspec 里
**谎报** `flutter: '>=3.0.0'`（实际需要 ≥3.38），所以 pub 认为它们可用；
到 3.5.0 才老实声明 `>=3.38.0`，但那时 pub 又会因 SDK 不符而跳过，
于是最终停在 3.4.4 —— 恰好是编不过的那一档。

**修法**（已写在 `pubspec.yaml` 里，两处叠加）：

```yaml
dependencies:
  media_kit_video: '>=1.2.4 <1.3.0'    # 只有 1.3.x 起才把 volume_controller 提到 ^3.0.2

dependency_overrides:
  volume_controller: '>=2.0.7 <3.0.0'  # 兜底：显式锁在 2.x
```

`media_kit_video` 1.2.x 依赖 `volume_controller ^2.0.7`（自己声明的是
`flutter: >=1.20.0`），整条链不含 UIScene 代码，在 Flutter 3.24.5 上正常。

> 仓库里**没有提交 `pubspec.lock`**（零本地环境路线下没有 `flutter pub get` 的产物），
> CI 每次都是全新解析依赖 —— 所以版本必须钉在 `pubspec.yaml` 里，指望 lockfile 是记不住的。

**退出条件**：Flutter 升到 **3.38.0+** 后，`volume_controller` 3.5.x / 3.7.x 均可用，
届时这两条约束都可以撤掉。

---

## 3. Windows 打包

> **本地没有 Flutter？** 直接跳到 [§4.9 云端构建 Windows 包](#49-windows-包的云端构建)。
> 两个工作流跑的是**同一套** `tool/package_windows.ps1`，产物完全一致。

### 3.1 一条命令

```powershell
# 便携版 zip
powershell -ExecutionPolicy Bypass -File tool/package_windows.ps1

# 便携版 + Inno Setup 安装包，并先清理
powershell -ExecutionPolicy Bypass -File tool/package_windows.ps1 -Clean -Installer

# 只重新打包（改打包脚本时用，省掉重复编译）
powershell -ExecutionPolicy Bypass -File tool/package_windows.ps1 -SkipBuild
```

| 参数 | 作用 |
|---|---|
| `-Mode release` | 构建模式（默认 release） |
| `-Installer` | 额外用 Inno Setup 出单文件安装包 |
| `-SkipBuild` | 复用已有产物，只重新打包 |
| `-NoZip` | 只出便携版目录，不压缩 |
| `-Clean` | 编译前先 `flutter clean` |

它做了这些事：读版本号 → `pub get` → `flutter build windows --release` →
**产物完整性校验** → 复制成便携版目录 → 写「使用说明.txt」→ 压缩 →（可选）Inno Setup。

### 3.2 产物结构

```
build\windows\x64\runner\Release\
  movie_hub.exe               主程序
  flutter_windows.dll         Flutter 引擎
  libmpv-2.dll                media_kit 播放内核（体积最大）
  *.dll                       各插件原生库
  data\
    app.so                    Dart AOT 代码
    icudtl.dat
    flutter_assets\           字体 / 图片 / assets/sample/
```

**这些文件的相对位置由 exe 写死，不能重新组织目录结构。**

脚本会校验三样东西，缺任何一样就直接报错而不是产出一个坏的包：

- `movie_hub.exe`
- `data\flutter_assets\`
- **`libmpv*.dll`** ← 少了它，应用能启动、能浏览，但一点播放就崩

### 3.3 为什么「便携版」是一个目录而不是单个 exe

Flutter 的 Windows Release 产物本质就是「exe + 引擎 dll + 资源目录」的组合，
没有官方的单文件输出。所以：

- **免安装便携版** = 把整个 `Release` 目录压成一个 zip，解压即用、可放 U 盘 ✅
- **单文件** 需要 MSIX 打包或自解压壳（7-Zip SFX 之类），对自用场景是纯粹的复杂度 ❌
- **想要正规安装体验** → 用 `-Installer` 出 Inno Setup 安装包 ✅

### 3.4 ⚠️ 目标机器的硬性依赖

**需要 Microsoft Visual C++ 2015-2022 可再发行组件 (x64)**

Flutter 的 Windows 模板默认动态链接 CRT（`/MD`）。目标机没有这个运行库时，
表现是**双击没反应**——没有对话框、事件日志里也难找，是最劝退的一类问题。

- 便携版：脚本生成的「使用说明.txt」里已写明，让对方自己装一次
  → <https://aka.ms/vs/17/release/vc_redist.x64.exe>
- 安装包：`movie_hub.iss` 里的 `[Code]` 段会在安装前**检测注册表**并提示用户
  （只警告不阻拦，因为运行库也可能由其它软件已经装上）

> 为什么用注册表判定而不是找 `vcruntime140.dll`：安装程序是 32 位进程，
> 访问 `System32` 会被 WOW64 重定向到 `SysWOW64`，在那里找 64 位运行库必然找不到。

### 3.5 常见失败

| 报错 | 原因 | 解决 |
|---|---|---|
| `Unable to find suitable Visual Studio toolchain` | 缺 MSVC 工具链 | VS Installer 勾「使用 C++ 的桌面开发」 |
| `MissingPluginException` / 功能异常 | 产物不完整（少了 dll 或 `data\`） | 别手工挑文件拷贝，用脚本 |
| 编译成功但双击没反应 | 目标机缺 VC++ 运行库 | 见 [§3.4](#34-️-目标机器的硬性依赖) |
| 改了代码产物没变 | 增量构建缓存残留 | `-Clean` 重跑 |
| 缺 `libmpv-2.dll` | 依赖树不完整 | 确认 `pubspec.yaml` 里有 `media_kit_libs_video` |

---

## 4. 推送到 GitHub 触发云端构建

### 4.1 创建仓库

在 GitHub 上新建一个仓库（**建议 Public**——macOS runner 对公开仓库免费且不限量；
私有仓库会消耗付费额度，且 arm64 runner 的可用性因套餐而异）。**不要**勾选
「Add a README / .gitignore / license」，保持空仓库。

### 4.2 最小推送流程（零本地环境）

**前提**：本地只需要 **Git**（<https://git-scm.com/download/win>，装默认选项即可）。
不需要 Flutter、不需要 Visual Studio、不需要 Python。

#### 第 1 步：在 GitHub 上建仓库

打开 <https://github.com/new>：

- **Repository name**：随便取，比如 `movie_hub`
- **Public / Private**：选 **Public**（公开仓库的 macOS / Windows runner 免费且不限量；
  私有仓库会消耗付费额度）
- **不要**勾选 "Add a README file" / ".gitignore" / "license" —— 保持**空仓库**

建完记下页面上的仓库地址，形如 `https://github.com/<你的用户名>/movie_hub.git`。

#### 第 2 步：本地推送（5 条命令）

在项目根目录打开终端（Git Bash 或 PowerShell 都行）：

```bash
cd <项目根目录>

git init
git branch -M main
git add .
git commit -m "chore: MovieHub 初始提交"
git remote add origin https://github.com/<你的用户名>/movie_hub.git
git push -u origin main
```

首次推送会弹出 GitHub 登录窗口（或让你输入用户名 + **Personal Access Token**，
不是账号密码 —— 密码方式已被 GitHub 废弃）。若嫌麻烦，装
[Git Credential Manager](https://github.com/git-ecosystem/git-credential-manager)
后首次登录会走浏览器授权。

推送完成后刷新仓库页面，应该在 **Actions** 标签页看到两个工作流已经在跑：
`Build iOS (Unsigned IPA)` 和 `Build Windows (Portable)`。

> **不需要**手工 `git add ios`。仓库里本来就没有 `ios/` / `windows/`，
> 它们完全由云端生成，不进版本库。
>
> `.gitignore` 已经写好，`build/`、`dist/`、`.dart_tool/`、`Pods/` 都不会被提交。
> 实测：待提交文件 110 个（96 个 `.dart` 源码 + 14 个配置 / 脚本 / 文档），
> `ios/`、`windows/`、`build/`、`dist/`、`Pods/`、`*.ipa` 全部被忽略。

#### 不想用命令行？用 GitHub Desktop

1. 装 <https://desktop.github.com>
2. `File → Add local repository` → 选项目根目录 → 提示不是仓库时点
   **create a repository**
3. 左下角填提交信息 → **Commit to main**
4. 顶部 **Publish repository** → **取消勾选 "Keep this code private"** → Publish

> **不推荐**用 GitHub 网页的 "uploading an existing file" 拖文件夹上传：
> 网页单次最多 100 个文件，而本项目有 110 个；而且要分两批、容易漏。
> 更要命的是网页上传**不会保留 `.gitattributes` 确立的行尾规则**，
> 上传的 YAML 可能带 CRLF 进仓库，让工作流在 runner 上报
> `$'\r': command not found`。

#### 第 3 步：等构建完成

在 Actions 页面点进某一次运行，展开步骤可以看实时日志。首次构建最慢
（iOS 要下载 MPVKit 原生库），通常 5~15 分钟。

| 工作流 | 产物 |
|---|---|
| `Build iOS (Unsigned IPA)` | `movie_hub-ios-unsigned-<版本>` → 内含 `movie_hub_unsigned.ipa` |
| `Build Windows (Portable)` | `movie_hub-windows-x64-<版本>` → 内含 `movie_hub-<版本>-windows-x64-portable.zip` |

> ⚠️ **GitHub 的 Artifact 下载下来是 `.zip`**，即使里面的文件本身叫 `.ipa`。
> 解压一次才能拿到真正的安装包。这是最容易让人以为「下载坏了」的一步。

<a id="42-最小推送流程零本地环境"></a>

<details>
<summary>附：仓库里会提交什么（点开）</summary>

```
lib/                     96 个 Dart 文件（业务代码）
docs/                    协议文档 + 本指南
tool/                    校验 / 补丁 / 打包脚本（含 installer/movie_hub.iss）
.github/workflows/       两个构建工作流
assets/sample/           示例订阅包
pubspec.yaml  README.md  analysis_options.yaml  .gitignore  .gitattributes
```

`ios/`、`windows/`、`build/`、`dist/` 都不在版本库里。

</details>

#### 打 tag 自动发 Release（可选）

想让两个平台的产物都挂到 Release 附件：

```bash
git tag v1.0.0
git push origin v1.0.0
```

两个工作流都会识别到 `v*` 标签并往**同一个** Release 追加附件
（iOS 加 `.ipa`，Windows 加 `.zip`）。`action-gh-release` 会复用已存在的
Release 而不是报错，所以并行是安全的。

发新版本时先改 `pubspec.yaml` 的 `version:`，提交后再打新 tag。

### 4.3 触发方式

| 方式 | 触发条件 | 用途 |
|---|---|---|
| 自动 | 推送到 `main` / `master` | 日常验证 |
| 自动 | 推送 `v*` 标签 | 出正式 Release（见 [§4.5](#45-打-tag-自动发布-release)） |
| 自动 | 开 / 更新 PR | 合并前验证（纯文档改动会跳过） |
| 手动 | Actions → 左侧选工作流 → **Run workflow** | 可调参数重跑（见 [§4.6](#46-工作流参数说明)） |

### 4.4 下载 Artifact

1. 打开 **Actions** → 点进某一次运行
2. 页面底部 **Artifacts** 区
3. 下载 `movie_hub-ios-unsigned-1.0.0+1`

> **注意**：GitHub 的 Artifact **下载下来是 .zip**，即使里面的文件叫 `.ipa`。
> 解压一次才能拿到 `movie_hub_unsigned.ipa`。这是最容易让人以为「下载坏了」的一步。

产物保留 30 天，过期后需要重新跑一次构建。

一次完整的 iOS 构建摘要也会写进该次运行的 **Summary** 页面（文件名、版本、大小、签名状态）。

### 4.5 打 tag 自动发布 Release

```powershell
git tag v1.0.0
git push origin v1.0.0
```

工作流会构建 → 自动创建 GitHub Release → 把 `.ipa` 作为附件上传。

要发新版本，先改 `pubspec.yaml` 的 `version:`，提交后再打 tag：

```powershell
# 编辑 pubspec.yaml: version: 1.0.1+2
git add pubspec.yaml
git commit -m "chore: bump version to 1.0.1"
git push origin main

git tag v1.0.1
git push origin v1.0.1
```

Release 链接形式：`https://github.com/<用户>/<仓库>/releases/download/v1.0.1/movie_hub_unsigned.ipa`

### 4.6 工作流参数说明

手动触发时（Run workflow）可以调这些：

| 参数 | 默认 | 说明 |
|---|---|---|
| `flutter-version` | `3.24.5` | **必须 ≥ 3.24.4**。runner 上是 Xcode 16，Flutter < 3.24.4 的 iOS 工具链不认识它引入的 module verifier，会报 `No such module 'Flutter'`。想用 3.22 线的话最低要 3.22.6（官方回传过兼容补丁），但不如直接用 3.24.5 稳 |
| `xcode-version` | 空 | 留空 = 用 runner 镜像默认（macos-15 上是 Xcode 16.x）。填了则用 `setup-xcode` 精确指定，比如 `16.4` |
| `build-mode` | `release` | `release` / `profile` / `debug` |
| `strip-signatures` | `false` | 剥离 `Runner.app` 内已嵌入的 `_CodeSignature`。**只有侧载工具报「签名无效 / 应用损坏」时才需要打开** |

**关于 runner 的两个坑：**

1. **用 `macos-15`，不要用 `macos-14`。** 很多网上的 Flutter 模板还在写 `macos-14`，
   但 GitHub 官方已公告：macos-14 镜像自 **2026-07-06** 起进入弃用期，
   **2026-11-02 起完全停止支持**。继续用会某天直接排队失败（no matching runner），
   而且失败信息和代码毫无关系。
2. **不要用 `macos-latest`。** 它的含义会随 GitHub 的迁移计划漂移，
   在你没改任何代码的情况下换掉 Xcode 版本，属于不可控变量。

### 4.7 macOS 分钟数成本

macOS runner 按 **10 倍**计费（公开仓库免费，但并发队列有限）。
工作流已经做了三件事控制成本：

- `concurrency.cancel-in-progress`：同分支连续推送会取消上一次构建
- `pull_request.paths-ignore`：PR 里的纯文档改动不触发构建
- `timeout-minutes: 60`：防止构建挂死时无限烧分钟

> `push` 事件刻意**没有**加 `paths-ignore`。原因：打 tag 时如果「相对上次提交只改了文档」，
> paths-ignore 会让构建被跳过，结果是 Release 里没有产物却完全看不出原因。
> 这类「静默跳过」比多花几分钟昂贵得多。

### 4.8 缓存

- **Flutter SDK + pub**：由 `subosito/flutter-action` 的 `cache: true` / `pub-cache: true` 处理
- **CocoaPods**：缓存 `~/Library/Caches/CocoaPods` 与 `ios/Pods`

> 缓存 key 用的是 `pubspec.lock` + `ios/Podfile` 的哈希，**不是** `ios/Podfile.lock`。
> 原因：Flutter 官方模板的 `ios/.gitignore` 会忽略 `Podfile.lock`，干净检出时该文件
> 不存在，`hashFiles` 返回空串 → key 恒定不变 → 改了依赖也照样命中旧缓存。
> 真正决定 pod 集合的是「插件列表（`pubspec.lock`）」+「Podfile 配置」。

iOS 首次构建设置最慢（要下载 MPVKit 原生库，体积较大），之后通常在几分钟内。

### 4.9 Windows 包的云端构建

`Build Windows (Portable)` 工作流在 **`windows-2022`** 上做这些事：

1. 装 Flutter（默认 3.24.5）
2. **按需生成 `windows/` 平台脚手架**（逻辑与 iOS 侧一致，临时目录生成后只拷目录）
3. `flutter pub get`
4. 调 `tool/package_windows.ps1` —— **与本地跑的是同一个脚本**，
   产物完整性校验（缺 `libmpv*.dll` 直接报错）也一并生效
5. 上传 `dist/*.zip` 与（可选）`dist/*setup*.exe`

**产物**：`movie_hub-<版本>-windows-x64-portable.zip`，解压即用。

> ⚠️ 目标电脑需要 **Microsoft Visual C++ 2015-2022 可再发行组件 (x64)**。
> zip 里附带的「使用说明.txt」已写明这一点，让对方装一次即可。

#### 为什么这里是 `windows-2022` 而**不是** `windows-latest`

这一行**不能**换成 `windows-latest`，否则编译必挂。原因是 runner 镜像漂移：

- GitHub 自 **2026-06-15** 起把 `windows-latest` / `windows-2025` 标签切到
  「Windows Server 2025 + **Visual Studio 2026 (18.5)**」；
- 而 Flutter 3.24.5 的 `packages/flutter_tools/lib/src/windows/visual_studio.dart`
  里，VS 大版本 → CMake 生成器的映射**只认 17**：

  ```dart
  String? get cmakeGenerator {
    return switch (_majorVersion) {
      17 => 'Visual Studio 17 2022',
      _  => 'Visual Studio 16 2019',   // ← VS 18 落在这里
    };
  }
  ```

- 于是 VS 2026 被算成 `'Visual Studio 16 2019'`，CMake 报：
  `Generator Visual Studio 16 2019 could not find any instance of Visual Studio.`

两个很容易踩空的点：

| 以为有用的做法 | 实际情况 |
|---|---|
| 设 `env: CMAKE_GENERATOR: "Visual Studio 17 2022"` | **无效**。Flutter 在 `build_windows.dart` 里是显式 `'-G', generator` 传给 cmake 的，会覆盖这个环境变量。flutter/flutter#180481 也确认 `CMAKE_GENERATOR` / `VSWHERE_ARGS` / PATH 覆盖都拦不住 |
| 在镜像上再装一个 VS 2022 | **无效**。Flutter 只挑「最新」的那个，有 VS 2026 时一定选 VS 2026 |

GitHub 官方给出的规避方式就是换镜像（runner-images#14017）：

> To continue using Visual Studio 2022, you can use the `windows-2022` Image.

`windows-2022` 带的是 VS 2022 (17.14)，正好映射到 `'Visual Studio 17 2022'`。
工作流里「打印工具链版本」那一步会用 `vswhere` 打出 VS 的 `displayName` 与版本号，
将来镜像再漂移时从这一行就能看出问题。

**退出条件**：Flutter 升到 **3.39.0+** 后（该版本已加入 VS 18 的映射）可以改回
`windows-latest`；在那之前别动这一行。

#### 手动触发时可调的参数

| 参数 | 默认 | 说明 |
|---|---|---|
| `flutter-version` | `3.24.5` | Flutter SDK 版本 |
| `build-installer` | `false` | 同时出 Inno Setup 安装包。runner 不预装 Inno Setup，打开后会先用 Chocolatey 现装一个（多约 1 分钟） |

#### 为什么 Windows 不需要 setup-java

Java 只有 Android 构建才需要。本项目的 Windows 桌面构建走 CMake + MSVC，
`windows-2022` 镜像已预装 **Visual Studio 2022**（含「使用 C++ 的桌面开发」工作负载）。

> 注意别用 `windows-latest`：它现在是 VS 2026，而 Flutter 3.24.5 认不出来 ——
> 原因见上面 [§4.9](#为什么这里是-windows-2022-而不是-windows-latest)。

#### 想在本机出安装包

先把 Flutter 装上，再：

```powershell
# 需先装 Inno Setup 6：https://jrsoftware.org/isdl.php
powershell -ExecutionPolicy Bypass -File tool/package_windows.ps1 -Installer
```

或者直接用手动触发工作流并把 `build-installer` 设为 `true`。

---

## 5. iOS 安装（未签名 IPA 怎么装上去）

### 5.0 三条路怎么选

| 方式 | 有效期 | 需要电脑 | 适合 |
|---|---|---|---|
| **TrollStore** | **永久** | 仅首次安装 TrollStore 需要 | ✅ 系统版本在支持区间内 → 首选 |
| **AltStore** | 7 天（自动续签） | 需要 AltServer 常驻 | 系统版本太新、不能用 TrollStore |
| **Sideloadly** | 7 天（手动重签） | 每次安装都要电脑 | 偶尔装一次，不想装常驻服务 |
| **SideStore** | 7 天（设备上自动续签） | 仅首次配对 | 类似 AltStore 但不用常驻电脑 |

**第一步永远是查系统版本**：设置 → 通用 → 关于本机 → 软件版本。

### 5.1 TrollStore 系统版本兼容表

TrollStore 靠 iOS 的 CoreTrust 漏洞实现「永久签名」。Apple 从 **iOS 17.0.1** 起修掉了它，
所以**这是硬件+系统版本决定的一次性机会**，不存在「以后会支持更高版本」。

| iOS / iPadOS 版本 | 是否支持 | 说明 |
|---|---|---|
| 14.0 – 15.4.1 | ✅ | 初代 TrollStore，全设备 |
| 15.5 – 16.6.1 | ✅ | TrollStore 2 |
| 16.7 RC (20H18) | ✅ | 仅 RC 版 |
| 17.0 | ✅ | 全 build |
| 16.7.x 正式版 / 17.0.1 及以上 | ❌ | CoreTrust 已修复 |
| 18.0+（含 26） | ❌ | **需要新漏洞，无法绕过** |

设备芯片维度：**A12–A17 / M1–M2 支持最好**；A8–A11 在 iOS 14.0–16.6.1 可用，
iOS 17.0 上受限（无公开内核漏洞）。

常见安装入口：

- **TrollInstallerX** —— 设备上直接装，iOS 14.0–16.6.1，最省事
- **TrollRestore** —— **需要一台电脑**（Windows 可用），iOS 15.2–17.0，最稳
- **TrollHelperOTA** —— 老系统（14.0–15.6.x）的 OTA 方式
- **Misaka** —— 通过已有工具引导

装好 TrollStore 后，去 **Settings → Installed ldid** 点一下（可能需要多试几次），
然后就能装 IPA 了。

### 5.2 TrollStore 安装本应用的步骤

1. 把 `movie_hub_unsigned.ipa` 传到手机上，三种方式任选：
   - **文件 App**：用 iCloud 云盘 / 数据线拷进「文件」，点击 → 分享 → 选 TrollStore
   - **微信/QQ**：把 IPA 发给自己，点开 → 用其他应用打开 → TrollStore
   - **Safari 下载**：把 IPA 传到任意直链（如本仓库的 Release 附件），Safari 打开下载 → 分享 → TrollStore
2. TrollStore 会自动重签并安装，几秒后桌面出现图标
3. 首次启动若提示「不受信任的开发者」——TrollStore 安装的应用正常不会有此提示；
   如果出现了，说明装的其实是别的工具，检查一下用的是不是 TrollStore

**卸载**：必须在 TrollStore 的 Apps 标签里卸载（桌面长按删除无效）。

**关于 entitlements**：TrollStore 会用 `ldid` 给二进制补上签名，并**原样保留**你提供的
entitlements。有三类 entitlement 在 iOS 15 / A12+ 上被禁用，带上会**启动即崩溃**：

- `com.apple.private.cs.debugger`
- `dynamic-codesigning`
- `com.apple.private.skip-library-validation`

> 本应用的 IPA 是 `--no-codesign` 产出的，不含任何 entitlements，因此天然规避这个问题。
> 反过来，如果你以后要手工加 entitlements，千万别加上面三个。

### 5.3 AltStore

**准备工作（Windows 侧）**：

1. 装 **iTunes**（必须是 Apple 官网版，不是 Microsoft Store 版）
   和 **iCloud**（同样要官网版）——AltServer 依赖它们的 Apple 设备通信组件
2. 从 <https://altstore.io> 下载并安装 AltServer
3. 手机用数据线连电脑

**安装**：

1. 电脑任务栏 AltServer 图标 → **Install AltStore** → 选你的设备
2. 输入你的 Apple ID（**建议用专用小号**）和密码
   > 如果开了双重认证，需要去 appleid.apple.com 生成一个**应用专用密码**
3. AltStore 装到手机后：设置 → 通用 → VPN与设备管理 → 信任你的开发者证书
4. 打开 AltStore → **My Apps** → 左上角 **+** → 选 `movie_hub_unsigned.ipa`
5. 等待签名安装完成

**之后每 7 天**：手机连上同一 Wi-Fi 且 AltServer 在跑时，AltStore 会自动后台续签。
也可以在 My Apps 里手动点 **Refresh All**。

**免费 Apple ID 的限制**：
- 每个 App 7 天有效期
- 同时最多 **3 个** 自签应用
- 每周最多申请 **10 个** App ID
- 每个 Bundle ID 要唯一（AltStore 会自动处理）

### 5.4 Sideloadly

最适合「偶尔装一次、不想装常驻服务」的场景。

1. Windows 装 **iTunes**（或 Apple Devices 应用）——提供 Apple 驱动
2. 从 <https://sideloadly.io> 下载 Sideloadly
3. 手机连线，Sideloadly 里会显示设备
4. 把 `movie_hub_unsigned.ipa` 拖进 **IPA** 框
5. 填 Apple ID（同样建议小号；开了 2FA 要用应用专用密码）
6. 点 **Start**，等待进度条走完
7. 手机上：设置 → 通用 → VPN与设备管理 → 信任证书

7 天后失效，重新连电脑跑一遍即可。

### 5.5 SideStore

和 AltStore 类似的 7 天签名，但**配对之后不再需要电脑**——
它用设备上的 VPN（StosVPN）把本地回环伪装成「本机 AltServer」来做续签。

1. 电脑装 AltServer + iTunes
2. 按 SideStore 官网指引完成首次配对（把 SideStore 的 IPA 通过 AltServer 装到设备）
3. 手机上开 StosVPN，在 SideStore 内导入 `movie_hub_unsigned.ipa`
4. 之后续签在设备上自动完成

适合「不想让电脑一直开着」的用户。首次配置比 AltStore 麻烦一些。

### 5.6 装完打不开 / 闪退的排查

| 现象 | 原因 | 解决 |
|---|---|---|
| 安装时提示「无法安装此 App」 | IPA 结构不合法（打包时符号链接被解引用） | 重新跑构建；工作流里已有链数守卫会拦住这种情况 |
| 提示「签名无效」/「应用已损坏」 | IPA 内嵌的旧签名与侧载工具冲突 | 手动触发构建时把 **`strip-signatures` 设为 `true`** 重跑 |
| 启动瞬间闪退 | 系统版本低于 App 的 `MinimumOSVersion`（13.0） | 换设备或换签名方式；确认 workflow 里的补丁步骤跑过了 |
| 能启动、浏览正常，一点播放就崩 | 播放内核缺失 | 不太可能（iOS 是静态链接进 framework），若出现请提 Issue 附 dSYM |
| 完全没有网络 / 搜不到内容 | ATS 没放行明文 HTTP | 确认 `Info.plist` 里有 `NSAllowsArbitraryLoads`；跑 `python tool/patch_ios_project.py --print` 核对 |
| 播放页锁不住横屏 | `Info.plist` 里缺 landscape 声明 | 见 [§2.3](#23-屏幕旋转)；跑一次补丁脚本 |
| 免费证书 7 天后打不开 | 正常现象 | AltStore 自动续签 / Sideloadly 重签 |
| TrollStore 装完图标点不动 | 图标缓存重载导致降级为 User 状态 | TrollStore 设置里装 persistence helper，或重新打开一次 TrollStore |

---

## 6. 故障排查总表

### 本地

| 现象 | 排查方向 |
|---|---|
| `flutter: command not found` | Flutter SDK 的 `bin` 没进 PATH |
| `flutter create` 后 `ios/` 是空的 | 命令末尾漏了 `.`（表示「在当前目录操作」） |
| `tool/package_windows.ps1` 报「执行策略禁止」 | 加 `-ExecutionPolicy Bypass`，或用 `powershell -File` 调用 |
| PowerShell 中文乱码 | 脚本是 UTF-8 **带 BOM**；如果你的编辑器把 BOM 去掉了，Windows PowerShell 5.1 会按 ANSI 解读 |
| Inno Setup 编译报「Unknown message name」 | 删掉 `[Messages]` 里对应那一行（不同 Inno 版本消息集合略有差异） |

### 云端

| 现象 | 排查方向 |
|---|---|
| 工作流排队失败「no matching runner」 | runner 标签失效。iOS 用 `macos-15`（**别用 `macos-14`**，2026-11-02 起不再支持）；Windows 用 `windows-2022`（**别用 `windows-latest`**，见下行） |
| Windows 报 `Generator Visual Studio 16 2019 could not find any instance of Visual Studio.` | `windows-latest` 自 2026-06-15 起换成了 VS 2026，Flutter 3.24.5 认不出 VS 18 → 回落成 2019 的生成器。改回 `runs-on: windows-2022`。**设 `CMAKE_GENERATOR` 或在镜像上装 VS 2022 都没用** —— 原因见 [§4.9](#为什么这里是-windows-2022-而不是-windows-latest) |
| 构建时报 `flutter create` 失败 | 云端脚手架生成步骤出错。检查 `--project-name movie_hub` 与 `--org` 是否合法（不能有连字符/中文）；这一步不需要仓库里预先存在 `ios/` |
| Dart 编译：`'ValueListenable' isn't a type`（`ValueNotifier` / `ChangeNotifier` / `debugPrint` / `kDebugMode` 同理） | 该文件只 `import 'package:flutter/material.dart'`。**`material.dart` 不提供这些类型** —— `packages/flutter/lib/widgets.dart` 只从 foundation 导出了 `UniqueKey`（`export 'foundation.dart' show UniqueKey;`）。补一行 `import 'package:flutter/foundation.dart';` 即可（与 material 同时导入不冲突） |
| Dart 编译：`Not a constant expression` / `Constant evaluation error` | `const` 表达式里混进了运行时值，典型是 `const EdgeInsets.only(bottom: margin)` —— `margin` 是方法参数。设计令牌（`AppSpacing.*` / `AppRadius.*` / `AppStroke.*` / `PlayerPalette.*`）都是 `static const`，可以进 `const`；参数和局部变量不行。**删掉那个 `const`**（不是改成别的常量） |
| Dart 编译：`Final field 'x' is not initialized` **外加**调用点 `No named parameter with the name 'x'` | 别顺着这两条去改字段和调用点 —— 真正的原因是**构造器签名本身非法**：把可选位置参数 `[...]` 和命名参数 `{...}` 混用了。Dart 明确禁止（ECMA-408 §9.2：*optional parameters can be specified either as a set of named parameters or as a list of positional parameters, **but not both***）。解析器丢掉 `{...}` 那一半，才连带报出"字段没初始化"和"没有这个命名参数"。修法是让 `message` 当必填位置参数，`url` / `cause` / `stackTrace` 走命名参数 |
| Dart 编译：`The type 'DioExceptionType' is not exhaustively matched by the switch cases` | `pubspec.yaml` 写的是 `dio: ^5.4.3+1`，而仓库**没有 `pubspec.lock`** ⇒ CI 每次解析到最新 5.x（5.8 起多了 `transformTimeout`）。**不要**去逐个补枚举成员，直接在 `switch` 里加 `default:` 兜底，这样上游再加枚举值也不会编译失败 |
| Dart 编译：`The value 'null' can't be returned from a function with return type 'bool'` | 返回类型写窄了。名字叫 `xxxOrNull` 就该声明成 `bool?`；**别改成返回 `false`** —— 那会把"字段缺失 / 格式不认识"和"明确为假"混成同一种结果，调用方再也分不清 |
| 报 `ios/Podfile 文件不存在` 或 `pod install` 找不到 Podfile | 补丁脚本本应在缺失时自动生成（见 [§1.3](#13-ios-工程补丁同样在云端跑含补出-podfile)）。看「应用 iOS 工程补丁」步骤日志里 `Podfile：` 那段自检输出定位 |
| `pod install` 报 `Platform :ios, '12.0'` 或部署版本冲突 | Podfile 用了 Flutter 默认模板、没走到我们的补丁。确认工作流里「应用 iOS 工程补丁」在 `pod install` **之前** |
| `No such module 'Flutter'` | Flutter 版本 < 3.24.4 配 Xcode 16。把 `flutter-version` 改到 3.24.4+ |
| `CocoaPods could not find compatible versions for pod "media_kit_libs_ios_video"` | 最低版本没抬到 13.0，或三处没改全。确认「应用 iOS 工程补丁」步骤没被跳过，并检查日志里是否出现 `post_install 结构非标准` 的 `[提示]` |
| Xcode 报 `Cannot find type 'FlutterSceneLifecycleDelegate' in scope`（文件是 `volume_controller-x.y.z`） | `volume_controller` 被解析到了 **3.4.2+**，它用了 Flutter 3.24.5 还没有的 UIScene 协议。`pubspec.yaml` 里已锁 `media_kit_video: '>=1.2.4 <1.3.0'` + `dependency_overrides: volume_controller: '>=2.0.7 <3.0.0'`。若又冒出来，先确认这两条没被人删掉 —— 详见 [§2.7](#27-ios-编不过volume_controller-的版本陷阱) |
| `ModuleCache.noindex/Session.modulevalidation` 不存在 | Xcode 15 写的模块缓存被 Xcode 16 读到。工作流每次都是干净环境，不会出现；本地出现就删 `~/Library/Developer/Xcode/DerivedData` |
| 构建成功但 Artifact 为空 | `flutter build ios` 实际失败了但被吞。翻「构建 iOS（未签名）」那一步的完整日志 |
| Release 里没有 IPA | tag 不是 `v` 开头（工作流用 `refs/tags/v` 判定） |

---

## 7. 合规提醒

本客户端**不内置任何影视站点、不内置任何爬虫代码、不提供任何内容源**。
数据源完全由用户以声明式 JSON 订阅导入（格式见
[`docs/SOURCE_PROTOCOL.md`](SOURCE_PROTOCOL.md)），客户端只做协议解释、聚合与播放。

- **TrollStore / AltStore / Sideloadly 均为第三方工具**，其使用条款与风险由你自行评估。
  特别是 TrollStore 依赖系统漏洞，可能影响系统稳定性，且 Apple 已在新系统中修复。
- 用**专用 Apple ID** 做侧载，不要用主力账号。
- 请自行确保所导入数据源的合法性，遵守相应站点服务条款及所在地区法律法规。

---

## 附：文件清单

```
.github/workflows/build-ios.yml     iOS 未签名 IPA 云端构建（含按需生成 ios/ 脚手架 + 打补丁）
.github/workflows/build-windows.yml Windows 便携版云端构建（含按需生成 windows/ 脚手架）
tool/scaffold_platforms.ps1         生成 ios/ windows/ 脚手架（本地有 Flutter 时可选）
tool/patch_ios_project.py           iOS 工程配置补丁（幂等）
tool/package_windows.ps1            Windows 一键打包（便携版 / 安装包）
tool/installer/movie_hub.iss        Inno Setup 安装包脚本（UTF-8 BOM）
tool/verify_structure.py            静态结构校验（无需 Flutter 工具链）
.gitignore                          提交过滤（build/ dist/ Pods/ *.ipa / 平台目录）
.gitattributes                      行尾规则（YAML 强制 LF，防 `$'\r'` 报错）
docs/BUILD_AND_RELEASE.md           本文档
docs/SOURCE_PROTOCOL.md             数据源订阅协议
```

> ℹ️ `ios/` 与 `windows/` **不在此清单内**——它们是构建时由云端生成的产物，
> 刻意不进版本库（见 [§1.2](#12-为什么在临时目录生成而不是在仓库里跑-flutter-create-)）。
