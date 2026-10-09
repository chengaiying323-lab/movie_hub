#!/usr/bin/env python3
"""MovieHub · iOS 工程配置补丁（幂等 / 跨平台 / 可在 Windows 上直接运行）。

为什么需要这个脚本
==========================================================================
`flutter create` 生成的 iOS 工程开箱**不能**满足本项目的三项硬需求：

1. **最低系统版本**. media_kit 在 iOS 上打包的是 `MPVKit`（libmpv 的 Apple 平台
   构建），其 podspec 声明 `platform :ios, '13.0'`。而 Flutter 脚手架默认写的是
   12.0 —— 两者不一致时 `pod install` 会直接失败：

       [!] CocoaPods could not find compatible versions for pod "media_kit_libs_ios_video"

   Xcode 工程（`project.pbxproj`）与 Podfile 是**两个独立的地方**，必须同时抬到
   13.0，只改一处仍然会失败。这是本项目 iOS 构建最常见的坑。

2. **明文 HTTP 放行**. 影视聚合场景里大量源站返回的是 `http://` 直链（而非 HTTPS）。
   iOS 的 ATS 默认拦截所有明文请求，不配置的话表现为"网络请求全部失败"，
   而且错误信息极其隐晦（`NSURLErrorAppTransportSecurityRequiresSecureConnection`
   往往被上层媒体库吞掉，只留一个"播放失败"）。

3. **Podfile 可能压根不存在**. 这是个反直觉的事实：`flutter create --platforms=ios`
   **不会**生成 `ios/Podfile`。Flutter 已把它从「app 模板」挪到了
   `templates/cocoapods/Podfile-ios`，只在真正需要跑 CocoaPods 时才由
   `flutter build` 按需投放。于是云端流程里（脚手架生成 → 打补丁 → pod install）
   轮到补丁这一步时，Podfile 还是缺的。
   所以本脚本在 Podfile 缺失时**直接生成一份标准模板**，而不是跳过或报错——
   跳过会让后续 `pod install` 拿到 Flutter 的默认 12.0，正是我们要避免的。

设计约定
==========================================================================
* **幂等**：重复执行不会产生副作用，也不会把已有值改坏（合并而非覆盖）。
* **只在必要时写盘**：内容没变就不碰文件，避免污染 git 工作区。
* **不缺就跳过、缺了就补齐**：Podfile 缺失时生成标准模板而非中断流程，
  因为中断会让整条云端构建卡在一个「本可以自动修复」的问题上。
* **不猜路径**：`ios/` 整个目录不存在时仍然明确报错并给出 `flutter create` 命令
  ——那种情况下缺的是整个 Xcode 工程，不是脚本能凭空造出来的。

用法
==========================================================================
    python tool/patch_ios_project.py              # 应用补丁（Podfile 缺失会自动生成）
    python tool/patch_ios_project.py --dry-run    # 只看会改什么，不写盘
    python tool/patch_ios_project.py --print      # 打印补齐后的关键配置，便于核对
"""

from __future__ import annotations

import argparse
import os
import plistlib
import re
import shutil
import sys
from pathlib import Path

# ── 常量 ────────────────────────────────────────────────────────────────────

#: media_kit / MPVKit 要求的最低 iOS 版本。Podfile 与 project.pbxproj 必须一致。
IOS_MIN_VERSION = "13.0"

#: 放行明文 HTTP。逐项理由：
#:   NSAllowsArbitraryLoads        —— 放开全部明文请求（视频直链主要靠这条）
#:   NSAllowsArbitraryLoadsInWebContent —— WebView 内的明文（内置浏览器/源站页面）
#:   NSAllowsLocalNetworking       —— 放行 127.0.0.1 / .local，便于本地代理与调试
#: 注意：这是"可用性优先"的取舍。若将来只接 HTTPS 源，应把第一条改为 false，
#: 仅保留按域名白名单的 NSExceptionDomains（更小的攻击面）。
ATS_KEYS = {
    "NSAllowsArbitraryLoads": True,
    "NSAllowsArbitraryLoadsInWebContent": True,
    "NSAllowsLocalNetworking": True,
}

#: 后台模式。只声明 audio：
#:   * audio —— 让 mpv 的音频输出在切后台后继续（配合 AVAudioSession）
#:   * picture-in-picture —— **刻意不声明**。media_kit 在 iOS 上走 libmpv 自绘纹理，
#:     不是 AVPlayerLayer，而系统级 PiP 只能挂载在 AVPlayerLayer 上。声明了也拿不到，
#:     反而会误导后续开发。真要做 PiP，需要改用 AVPlayer 后端或自行实现
#:     AVPictureInPictureController + 一条等价的播放管线。
BACKGROUND_MODES = ["audio"]

#: 屏幕方向。**必须四个方向都列**（含 iPad 的倒置竖屏）。
#: 关键点：Info.plist 声明的是"应用允许出现的方向全集"，
#: Dart 侧 `SystemChrome.setPreferredOrientations` 只能在这个全集**之内**收窄。
#: 也就是说——播放页想锁横屏，Info.plist 里就**必须**先有 landscape；
#: 只写竖屏的话，播放页那句锁定横屏会静默失效（这是移动端最常见的"锁不住"原因）。
ORIENTATIONS_PHONE = [
    "UIInterfaceOrientationPortrait",
    "UIInterfaceOrientationLandscapeLeft",
    "UIInterfaceOrientationLandscapeRight",
]
ORIENTATIONS_PAD = ORIENTATIONS_PHONE + ["UIInterfaceOrientationPortraitUpsideDown"]

#: 其余布尔键及其理由。
EXTRA_PLIST_BOOLS = {
    # 播放页用 `SystemChrome.setEnabledSystemUIMode(immersiveSticky)` 隐藏状态栏。
    # iOS 上要由 Flutter 接管状态栏显隐，这个键必须为 false（否则系统说了算）。
    "UIViewControllerBasedStatusBarAppearance": False,
    # iPad 默认支持分屏多任务，此时系统会忽略方向锁定、且窗口可被任意拖拽缩放。
    # 播放器需要稳定的横屏画布，因此要求"必须全屏"。
    # 代价：应用不会再出现在 iPad 分屏列表中——对视频播放器是合理取舍。
    "UIRequiresFullScreen": True,
    # ProMotion（120Hz）机型默认把 Flutter 的自绘帧率压在 60Hz。
    # 打开后动画/滚动才真正跑到 120Hz。
    "CADisableMinimumFrameDurationOnPhone": True,
    # 触控板/鼠标的间接输入事件（桌面级指针语义），Flutter 模板推荐开启。
    "UIApplicationSupportsIndirectInputEvents": True,
    # 本应用不实现任何"非豁免加密"（只有系统 HTTPS/标准库密码学），
    # 显式声明可跳过 App Store 每次上传都要回答的出口合规问询。
    "ITSAppUsesNonExemptEncryption": False,
}

PLIST_PATH = Path("ios/Runner/Info.plist")
PODFILE_PATH = Path("ios/Podfile")
PBXPROJ_PATH = Path("ios/Runner.xcodeproj/project.pbxproj")

#: Flutter SDK 里官方 Podfile 模板的位置（相对 FLUTTER_ROOT）。
SDK_PODFILE_TEMPLATE = Path("packages/flutter_tools/templates/cocoapods/Podfile-ios")

#: 内置兜底模板 —— Flutter 官方 `Podfile-ios` 的等价副本（对齐 3.24 线）。
#:
#: 只在找不到 Flutter SDK 时才用（例如有人在没装 Flutter 的机器上跑本脚本）。
#: 云端构建时 `flutter` 一定在 PATH 上，会优先取 SDK 自带的模板，
#: 这样模板的演进（比如将来 podhelper 新增了必须调用的 hook）能自动跟随，
#: 不会因为这份副本过时而漏掉。
PODFILE_FALLBACK_TEMPLATE = """\
# Uncomment this line to define a global platform for your project
# platform :ios, '12.0'

# CocoaPods analytics sends network stats synchronously affecting flutter build latency.
ENV['COCOAPODS_DISABLE_STATS'] = 'true'

project 'Runner', {
  'Debug' => :debug,
  'Profile' => :release,
  'Release' => :release,
}

def flutter_root
  generated_xcode_build_settings_path = File.expand_path(File.join('..', 'Flutter', 'Generated.xcconfig'), __FILE__)
  unless File.exist?(generated_xcode_build_settings_path)
    raise "#{generated_xcode_build_settings_path} must exist. If you're running pod install manually, make sure flutter pub get is executed first"
  end

  File.foreach(generated_xcode_build_settings_path) do |line|
    matches = line.match(/FLUTTER_ROOT\\=(.*)/)
    return matches[1].strip if matches
  end
  raise "FLUTTER_ROOT not found in #{generated_xcode_build_settings_path}. Try deleting Generated.xcconfig, then run flutter pub get"
end

require File.expand_path(File.join('packages', 'flutter_tools', 'bin', 'podhelper'), flutter_root)

# flutter_ios_podfile_setup 由 podhelper.rb 提供（Flutter 3.16+，SwiftPM 支持用）。
# 它是 Object 上的**私有**方法，respond_to? 必须补第二个参数 true 才认，否则守卫恒为假。
# 老版本 Flutter 没有这个方法，那时跳过正是正确行为（硬调用会抛 NoMethodError 让 pod install 失败）。
flutter_ios_podfile_setup if respond_to?(:flutter_ios_podfile_setup, true)

target 'Runner' do
  use_frameworks!

  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
  target 'RunnerTests' do
    inherit! :search_paths
  end
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
  end
end
"""

# ── 小工具 ──────────────────────────────────────────────────────────────────


def _norm(version: str) -> tuple[int, ...]:
    """把 '13.0' / '12.4' 这类版本串变成可比较的元组。"""
    parts: list[int] = []
    for chunk in version.split("."):
        digits = "".join(ch for ch in chunk if ch.isdigit())
        parts.append(int(digits) if digits else 0)
    return tuple(parts)


def _is_older(current: str, target: str) -> bool:
    return _norm(current) < _norm(target)


class Report:
    """收集变更项，最后统一打印——避免一边改一边刷屏难以核对。"""

    def __init__(self) -> None:
        # (文件, 种类, 描述)；种类 'change' | 'note'
        self.lines: list[tuple[str, str, str]] = []

    def add(self, file: str, desc: str) -> None:
        """记录一次真实变更。"""
        self.lines.append((file, "change", desc))

    def note(self, file: str, desc: str) -> None:
        """记录一条与变更无关的提示（不要和变更混在一起打同一个前缀）。"""
        self.lines.append((file, "note", desc))

    def dump(self, *, dry_run: bool) -> None:
        if not self.lines:
            print("  （无需变更，工程已是最新配置）")
            return
        current = None
        for file, kind, desc in self.lines:
            if file != current:
                current = file
                print(f"  {file}")
            if kind == "change":
                prefix = "[将改]" if dry_run else "[已改]"
            else:
                prefix = "[提示]"
            print(f"    {prefix} {desc}")


# ── Info.plist ──────────────────────────────────────────────────────────────


def patch_info_plist(root: Path, report: Report, dry_run: bool) -> bool:
    """补齐 Info.plist。返回是否发生了变更。"""
    path = root / PLIST_PATH
    if not path.exists():
        report.note(str(PLIST_PATH), "文件不存在，跳过（先运行 flutter create --platforms=ios .）")
        return False

    with path.open("rb") as fp:
        plist = plistlib.load(fp)

    changed = False

    # 1) ATS —— 整体合并（已有的子键保留，例如用户自配的 NSExceptionDomains）
    ats = plist.get("NSAppTransportSecurity")
    if not isinstance(ats, dict):
        ats = {}
    for key, value in ATS_KEYS.items():
        if ats.get(key) != value:
            ats[key] = value
            report.add(str(PLIST_PATH), f"NSAppTransportSecurity.{key} = {str(value).lower()}")
            changed = True
    # 显式写出整个 dict，保证"原本完全没有这个键"的情况也会被补上
    if plist.get("NSAppTransportSecurity") != ats:
        plist["NSAppTransportSecurity"] = ats
        changed = True

    # 2) 后台模式 —— 取并集，不覆盖（将来手工加了别的模式不会被抹掉）
    modes = plist.get("UIBackgroundModes")
    if not isinstance(modes, list):
        modes = []
    merged_modes = list(modes)
    for mode in BACKGROUND_MODES:
        if mode not in merged_modes:
            merged_modes.append(mode)
            report.add(str(PLIST_PATH), f"UIBackgroundModes += {mode}")
            changed = True
    if merged_modes != modes or "UIBackgroundModes" not in plist:
        plist["UIBackgroundModes"] = merged_modes
        changed = True

    # 3) 方向 —— 同样取并集，但用固定顺序输出，避免每次运行顺序抖动
    for key, required in (
        ("UISupportedInterfaceOrientations", ORIENTATIONS_PHONE),
        ("UISupportedInterfaceOrientations~ipad", ORIENTATIONS_PAD),
    ):
        existing = plist.get(key)
        if not isinstance(existing, list):
            existing = []
        added = [o for o in required if o not in existing]
        if added:
            ordered = [o for o in required if o in existing or o in added]
            plist[key] = ordered
            report.add(str(PLIST_PATH), f"{key} += {', '.join(o.replace('UIInterfaceOrientation', '') for o in added)}")
            changed = True

    # 4) 其余布尔键
    for key, value in EXTRA_PLIST_BOOLS.items():
        if plist.get(key) != value:
            plist[key] = value
            report.add(str(PLIST_PATH), f"{key} = {str(value).lower()}")
            changed = True

    if changed and not dry_run:
        with path.open("wb") as fp:
            plistlib.dump(plist, fp, fmt=plistlib.FMT_XML, sort_keys=False)

    return changed


# ── Podfile ─────────────────────────────────────────────────────────────────

_PODFILE_PLATFORM_RE = re.compile(
    r"^(?P<indent>\s*)(?P<comment>#\s*)?platform\s+:ios\s*,\s*'(?P<version>[^']*)'",
    re.M,
)

#: Flutter 官方模板里 post_install 中那一行标准调用。用它当锚点做注入，
#: 因为这一行由 Flutter 自己生成、拼写稳定，比去解析任意 Ruby 的 block 结构可靠得多。
#:
#: `(?=\r?$)` 用零宽前瞻而不是直接把 `\r` 写进模式：`$` 在 re.M 下匹配的是 `\n`
#: 之前的位置，CRLF 文件里它前面还留着一个 `\r`。若写成 `[ \t]*\r?$`，这个 `\r`
#: 会被**消费掉**，插入点就落到 `\n` 与 `\r` 之间，把原来那一行的行尾切成一个
#: 孤立 LF（实测过：CRLF 文件里会混进 1 个裸 `\n`）。前瞻只判断不消费，
#: 插入点才会准确地落在 `\r` 之前，LF / CRLF 两种文件都能保持原有行尾不变。
_POST_INSTALL_CALL_RE = re.compile(
    r"^(?P<indent>[ \t]*)flutter_additional_ios_build_settings\(target\)[ \t]*(?=\r?$)",
    re.M,
)


def _flutter_root() -> Path | None:
    """定位 FLUTTER_ROOT：先看环境变量，再顺着 PATH 上的 flutter 可执行文件反推。"""
    env = os.environ.get("FLUTTER_ROOT", "").strip()
    if env:
        candidate = Path(env)
        if candidate.is_dir():
            return candidate

    exe = shutil.which("flutter")
    if not exe:
        return None
    # 布局固定为 <FLUTTER_ROOT>/bin/flutter（Windows 上是 bin/flutter.bat）
    root = Path(exe).resolve().parent.parent
    return root if root.is_dir() else None


def _locate_sdk_podfile_template() -> Path | None:
    """返回 Flutter SDK 自带的 Podfile 模板路径，找不到则 None。"""
    root = _flutter_root()
    if root is None:
        return None
    candidate = root / SDK_PODFILE_TEMPLATE
    return candidate if candidate.is_file() else None


def build_podfile_text(min_version: str) -> tuple[str, str]:
    """产出 Podfile 初始文本。返回 (文本, 来源说明)。

    优先用「当前安装的 Flutter SDK 自带的官方模板」，这样模板演进能自动跟随；
    取不到时才退回内置副本。两条路径最终都会被下面的规范化步骤改成
    `platform :ios, min_version` + post_install 强制部署版本。
    """
    template = _locate_sdk_podfile_template()
    if template is not None:
        try:
            return template.read_text(encoding="utf-8"), f"Flutter SDK 模板 {template}"
        except OSError:
            pass
    return PODFILE_FALLBACK_TEMPLATE, "内置模板（未在 PATH 上找到 Flutter SDK）"


def _ensure_post_install_target(text: str, min_version: str) -> tuple[str, str]:
    """确保 post_install 把 Pods 目标的部署版本钉在 min_version。

    返回 (新文本, 动作)，动作取值：
      'already'     —— 已经有了，不动
      'injected'    —— 已注入覆盖代码
      'unsupported' —— post_install 结构非标准，找不到可靠锚点（调用方只提示不阻断）

    为什么非要有这一步：`flutter_additional_ios_build_settings` 会把 Pods 目标的
    `IPHONEOS_DEPLOYMENT_TARGET` 拉回 Flutter 自己的默认值（3.24 线是 12.0），
    而 MPVKit 要求 13.0。所以覆盖必须写在**它之后**才会生效。
    """
    if "IPHONEOS_DEPLOYMENT_TARGET" in text:
        return text, "already"

    match = _POST_INSTALL_CALL_RE.search(text)
    if not match:
        return text, "unsupported"

    eol = "\r\n" if "\r\n" in text else "\n"
    indent = match.group("indent")
    base = indent          # 与锚点同级，视觉上才是 each 块里的兄弟语句
    inner = indent + "  "
    block = eol.join(
        [
            "",
            f"{base}# 强制 Pods 目标的部署版本。media_kit 在 iOS 上打包的是 MPVKit，",
            f"{base}# 它要求 iOS {min_version}；而上一行的 flutter_additional_ios_build_settings",
            f"{base}# 会把目标拉回 Flutter 默认值，所以覆盖必须写在它之后才生效。",
            f"{base}target.build_configurations.each do |config|",
            f"{inner}config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '{min_version}'",
            f"{base}end",
        ]
    )
    return text[: match.end()] + block + text[match.end() :], "injected"


def _read_text(path: Path) -> str:
    """按原样读入（newline='' 关闭通用换行转换），避免改写时把行尾风格搞乱。"""
    with path.open("r", encoding="utf-8", newline="") as fp:
        return fp.read()


def _write_text(path: Path, text: str) -> None:
    with path.open("w", encoding="utf-8", newline="") as fp:
        fp.write(text)


def patch_podfile(root: Path, report: Report, dry_run: bool) -> bool:
    """确保 Podfile 存在、平台版本为 IOS_MIN_VERSION、且 post_install 钉住部署版本。

    `flutter create` **不会**生成 Podfile（见模块文档第 3 点），所以这里缺失时
    直接生成一份标准模板，而不是跳过或报错。
    """
    path = root / PODFILE_PATH
    created = False

    if path.exists():
        text = _read_text(path)
    else:
        text, source = build_podfile_text(IOS_MIN_VERSION)
        created = True
        report.add(str(PODFILE_PATH), f"文件不存在 → 生成标准模板（来源：{source}）")

    changed = created
    eol = "\r\n" if "\r\n" in text else "\n"

    # 1) 全局 platform —— 决定 CocoaPods 的依赖解析版本
    match = _PODFILE_PLATFORM_RE.search(text)
    if match:
        current = match.group("version")
        commented = bool(match.group("comment"))
        if commented or _is_older(current, IOS_MIN_VERSION):
            replacement = f"{match.group('indent')}platform :ios, '{IOS_MIN_VERSION}'"
            text = text[: match.start()] + replacement + text[match.end() :]
            report.add(
                str(PODFILE_PATH),
                f"platform :ios, '{current}' → '{IOS_MIN_VERSION}'"
                + ("（原本被注释，等同未声明）" if commented else ""),
            )
            changed = True
        elif created:
            report.add(str(PODFILE_PATH), f"platform :ios, '{current}'（模板已符合要求，未改动）")
    else:
        # 没有 platform 行：插到 `project 'Runner'` 之前，
        # 保证它在 CocoaPods 解析依赖之前就生效。
        anchor = re.search(r"^project\s+'Runner'", text, re.M)
        line = f"platform :ios, '{IOS_MIN_VERSION}'{eol}"
        text = (text[: anchor.start()] + line + text[anchor.start() :]) if anchor else line + text
        report.add(str(PODFILE_PATH), f"新增 platform :ios, '{IOS_MIN_VERSION}'")
        changed = True

    # 2) post_install —— 决定 Pods 目标实际编译时的部署版本
    text, action = _ensure_post_install_target(text, IOS_MIN_VERSION)
    if action == "injected":
        report.add(
            str(PODFILE_PATH),
            f"post_install += 强制 IPHONEOS_DEPLOYMENT_TARGET = {IOS_MIN_VERSION}",
        )
        changed = True
    elif action == "already" and created:
        report.add(str(PODFILE_PATH), "post_install 已含 IPHONEOS_DEPLOYMENT_TARGET 覆盖")
    elif action == "unsupported":
        report.note(
            str(PODFILE_PATH),
            "post_install 结构非标准，未注入部署版本覆盖；"
            f"若 pod install 报版本冲突，请手工确保 Pods 目标是 iOS {IOS_MIN_VERSION}",
        )

    if changed and not dry_run:
        _write_text(path, text)
    return changed


# ── Xcode 工程（project.pbxproj） ────────────────────────────────────────────

_PBX_TARGET_RE = re.compile(r"(IPHONEOS_DEPLOYMENT_TARGET\s*=\s*)([\d.]+)(\s*;)")


def patch_pbxproj(root: Path, report: Report, dry_run: bool) -> bool:
    """把 Xcode 工程的 IPHONEOS_DEPLOYMENT_TARGET 抬到 IOS_MIN_VERSION。

    必须与 Podfile 同时改：Xcode 工程决定实际编译的 target 版本，
    Podfile 决定 CocoaPods 的依赖解析版本。只改一处会在 `pod install`
    或链接阶段报错，而且报错信息指向的是 pod 而不是这里，很容易查错方向。
    """
    path = root / PBXPROJ_PATH
    if not path.exists():
        report.note(str(PBXPROJ_PATH), "文件不存在，跳过")
        return False

    text = _read_text(path)

    bumped_versions: set[str] = set()
    hit_count = 0

    def _sub(match: re.Match[str]) -> str:
        nonlocal hit_count
        current = match.group(2)
        if _is_older(current, IOS_MIN_VERSION):
            bumped_versions.add(current)
            hit_count += 1
            return f"{match.group(1)}{IOS_MIN_VERSION}{match.group(3)}"
        return match.group(0)

    new_text = _PBX_TARGET_RE.sub(_sub, text)
    if new_text == text:
        return False

    # 同一份工程里 Debug / Profile / Release 三套 build configuration 都带这个键，
    # 所以命中的处数通常是 3 的倍数——报"处数"而不是"版本数"，才看得出改全了没有。
    report.add(
        str(PBXPROJ_PATH),
        f"IPHONEOS_DEPLOYMENT_TARGET: {'/'.join(sorted(bumped_versions))} → {IOS_MIN_VERSION}"
        f"（共 {hit_count} 处，覆盖所有 build configuration）",
    )
    if not dry_run:
        _write_text(path, new_text)
    return True


# ── 自检输出 ────────────────────────────────────────────────────────────────


def print_summary(root: Path) -> None:
    """打印补齐后的关键键位，供人工核对。"""
    path = root / PLIST_PATH
    if path.exists():
        with path.open("rb") as fp:
            plist = plistlib.load(fp)

        print("\n  Info.plist 关键配置：")
        ats = plist.get("NSAppTransportSecurity", {})
        print(f"    NSAllowsArbitraryLoads              = {ats.get('NSAllowsArbitraryLoads')}")
        print(f"    UIBackgroundModes                   = {plist.get('UIBackgroundModes')}")
        print(f"    UISupportedInterfaceOrientations    = {plist.get('UISupportedInterfaceOrientations')}")
        print(f"    ...~ipad                            = {plist.get('UISupportedInterfaceOrientations~ipad')}")
        print(f"    UIViewControllerBasedStatusBarAppearance = {plist.get('UIViewControllerBasedStatusBarAppearance')}")
        print(f"    UIRequiresFullScreen                = {plist.get('UIRequiresFullScreen')}")
        print(f"    CADisableMinimumFrameDurationOnPhone= {plist.get('CADisableMinimumFrameDurationOnPhone')}")
        print(f"    ITSAppUsesNonExemptEncryption       = {plist.get('ITSAppUsesNonExemptEncryption')}")
    else:
        print(f"\n  Info.plist：不存在（{PLIST_PATH}）")

    # Podfile 的状态放在这里打印，而不是靠工作流里的 `test -f` 断言：
    # 断言只会在生成路径变化时制造假失败、挡住整条构建；打印出来同样能核对，
    # 而且不阻断后续的 pod install / flutter build。
    podfile = root / PODFILE_PATH
    print("\n  Podfile：")
    if not podfile.exists():
        print(f"    [警告] 仍不存在（{PODFILE_PATH}）—— pod install 会失败，请检查上一步是否报错")
        return
    raw = _read_text(podfile)
    platform = _PODFILE_PLATFORM_RE.search(raw)
    if platform:
        state = "被注释 = 未生效" if platform.group("comment") else "生效"
        print(f"    platform :ios, '{platform.group('version')}'（{state}）")
    else:
        print("    platform :ios —— 未声明（CocoaPods 会退回工程自身的部署版本）")
    print(
        "    post_install 强制部署版本              = "
        + ("是" if "IPHONEOS_DEPLOYMENT_TARGET" in raw else "否")
    )
    print(f"    podhelper 引导（flutter_root / pods）  = " + ("是" if "flutter_install_all_ios_pods" in raw else "否"))


def find_project_root(start: Path) -> Path:
    """向上查找含 pubspec.yaml 的目录。"""
    for candidate in [start, *start.parents]:
        if (candidate / "pubspec.yaml").exists():
            return candidate
    return start


HINT = """
ios/ 工程不存在。请先在项目根目录执行：

    flutter create --platforms=ios .

（这条命令只补 ios/ 目录，不会覆盖 lib/ 下的既有代码。
 注意：它**不会**生成 ios/Podfile —— 那正是本脚本接下来要补的东西。）

若你在本机没有 Flutter，不需要装：GitHub Actions 的
.github/workflows/build-ios.yml 会在构建前自动完成「生成脚手架 + 打补丁」。
"""


def main() -> int:
    parser = argparse.ArgumentParser(description="MovieHub iOS 工程配置补丁")
    parser.add_argument("--dry-run", action="store_true", help="只显示将要做的修改，不写盘")
    parser.add_argument(
        "--print",
        dest="do_print",
        action="store_true",
        help="打印补齐后的关键配置（Info.plist 键 + Podfile 状态），便于核对",
    )
    parser.add_argument("--project-root", type=Path, default=None, help="项目根目录（默认自动查找）")
    args = parser.parse_args()

    root = args.project_root or find_project_root(Path(__file__).resolve().parent)
    ios_dir = root / "ios"

    print(f"MovieHub · iOS 工程补丁 · {root}{'  [DRY-RUN]' if args.dry_run else ''}")
    print(f"目标最低 iOS 版本：{IOS_MIN_VERSION}（media_kit / MPVKit 要求）\n")

    if not ios_dir.is_dir():
        print(HINT, file=sys.stderr)
        return 2

    report = Report()
    patch_info_plist(root, report, args.dry_run)
    patch_podfile(root, report, args.dry_run)
    patch_pbxproj(root, report, args.dry_run)
    report.dump(dry_run=args.dry_run)

    if args.do_print:
        print_summary(root)

    if args.dry_run:
        print("\n（--dry-run：未写入任何文件）")
    else:
        print("\n完成。ios/ 是构建产物，不进版本库（已由 .gitignore 忽略）。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
