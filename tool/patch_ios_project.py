#!/usr/bin/env python3
"""MovieHub · iOS 工程配置补丁（幂等 / 跨平台 / 可在 Windows 上直接运行）。

为什么需要这个脚本
==========================================================================
`flutter create` 生成的 iOS 工程开箱**不能**满足本项目的两项硬需求：

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

除了这两项，脚本还会补齐播放类应用需要的一组 Info.plist 键（后台音频、旋转、
沉浸式状态栏、iPad 全屏），每一项都在下面的常量旁写了理由。

设计约定
==========================================================================
* **幂等**：重复执行不会产生副作用，也不会把已有值改坏（合并而非覆盖）。
* **只在必要时写盘**：内容没变就不碰文件，避免污染 git 工作区。
* **不猜路径**：`ios/` 不存在时明确报错并给出 `flutter create` 命令，
  而不是悄悄跳过——静默跳过会让人以为"已经配好了"。

用法
==========================================================================
    python tool/patch_ios_project.py              # 应用补丁
    python tool/patch_ios_project.py --dry-run    # 只看会改什么，不写盘
    python tool/patch_ios_project.py --print      # 打印补齐后的关键 Info.plist 键
"""

from __future__ import annotations

import argparse
import plistlib
import re
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
        self.lines: list[tuple[str, str]] = []  # (文件, 描述)

    def add(self, file: str, desc: str) -> None:
        self.lines.append((file, desc))

    def note(self, file: str, desc: str) -> None:
        self.lines.append((file, desc))

    def dump(self, *, dry_run: bool) -> None:
        if not self.lines:
            print("  （无需变更，工程已是最新配置）")
            return
        current = None
        for file, desc in self.lines:
            if file != current:
                current = file
                print(f"  {file}")
            prefix = "[将改]" if dry_run else "[已改]"
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


def patch_podfile(root: Path, report: Report, dry_run: bool) -> bool:
    """把 Podfile 的全局 platform 抬到 IOS_MIN_VERSION。"""
    path = root / PODFILE_PATH
    if not path.exists():
        report.note(str(PODFILE_PATH), "文件不存在，跳过")
        return False

    text = path.read_text(encoding="utf-8")
    match = _PODFILE_PLATFORM_RE.search(text)

    if match:
        current = match.group("version")
        commented = bool(match.group("comment"))
        if not commented and not _is_older(current, IOS_MIN_VERSION):
            return False
        replacement = f"{match.group('indent')}platform :ios, '{IOS_MIN_VERSION}'"
        text = text[: match.start()] + replacement + text[match.end() :]
        report.add(
            str(PODFILE_PATH),
            f"platform :ios, '{current}' → '{IOS_MIN_VERSION}'" + ("（原本被注释）" if commented else ""),
        )
    else:
        # 没有 platform 行：插入到 `project 'Runner'` 之前，
        # 保证它在 CocoaPods 解析依赖之前就生效。
        anchor = re.search(r"^project\s+'Runner'", text, re.M)
        line = f"platform :ios, '{IOS_MIN_VERSION}'\n"
        if anchor:
            text = text[: anchor.start()] + line + text[anchor.start() :]
        else:
            text = line + text
        report.add(str(PODFILE_PATH), f"新增 platform :ios, '{IOS_MIN_VERSION}'")

    if not dry_run:
        path.write_text(text, encoding="utf-8")
    return True


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

    text = path.read_text(encoding="utf-8")

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
        path.write_text(new_text, encoding="utf-8")
    return True


# ── 自检输出 ────────────────────────────────────────────────────────────────


def print_summary(root: Path) -> None:
    """打印补齐后的关键键位，供人工核对。"""
    path = root / PLIST_PATH
    if not path.exists():
        return
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
 生成的 ios/ 目录需要提交进 Git，云端构建才能拿到它。）
"""


def main() -> int:
    parser = argparse.ArgumentParser(description="MovieHub iOS 工程配置补丁")
    parser.add_argument("--dry-run", action="store_true", help="只显示将要做的修改，不写盘")
    parser.add_argument("--print", dest="do_print", action="store_true", help="打印补齐后的关键 Info.plist 键")
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
        print("\n完成。记得把 ios/ 目录一起提交进 Git，云端构建依赖它。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
