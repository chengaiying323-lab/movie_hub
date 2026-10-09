#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""MovieHub 结构静态校验（无需 Flutter/Dart 工具链）。

用途
------------------------------------------------------------------
`flutter analyze` 需要完整工具链；本脚本只做**语法无关的结构校验**，
在 CI 之前的快速自检、或纯文本编辑后的即时验证中很有用：

  A. 所有相对 import/export 路径能否解析到真实文件
  B. 未使用的相对 import（按被导入文件导出的公开符号判定）
  C. 设计令牌成员引用（如 `AppColors.ink`）是否存在
  D. Provider 标识符是否均有定义
  E. 构造调用实参是否与形参表匹配（支持 `{命名}` / `[可选位置]` 混排）
  F. 命名构造函数与关键工具类的成员引用是否存在
  G. 死代码：定义了但全项目从未引用的公开类型

用法
------------------------------------------------------------------
    python tool/verify_structure.py

退出码：0 = 通过；1 = 发现问题。
"""

from __future__ import annotations

import os
import re
import sys

# 脚本位于 <project>/tool/ 下，因此 lib 在上两级
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB_ROOT = os.path.join(PROJECT_ROOT, "lib")

# ── Flutter / Dart SDK 类型白名单（用于检查 G 的降噪） ──────────────
SDK_TYPES = set(
    """
Widget StatelessWidget StatefulWidget State BuildContext Color Colors Size Offset Rect
EdgeInsets EdgeInsetsGeometry BorderRadius BoxDecoration BoxShadow BoxConstraints Gradient
LinearGradient Alignment TextAlign TextStyle FontWeight TextOverflow TextPainter TextSpan
TextEditingController FocusNode MediaQuery MediaQueryData ThemeData Theme ColorScheme
TextTheme IconData Icons Image ImageProvider DecorationImage BoxFit Clip ClipRRect
Navigator NavigatorState MaterialPageRoute PageRoute PageRouteBuilder Route Scaffold
ScaffoldMessenger SnackBar AppBar CustomScrollView SliverList SliverGrid SliverPadding
SliverToBoxAdapter SliverFillRemaining ScrollController ScrollPhysics ScrollView
PageController PageView AnimationController Animation AnimationStatus CurvedAnimation Tween
AnimatedContainer AnimatedOpacity AnimatedSwitcher AnimatedBuilder AnimatedDefaultTextStyle
AnimatedAlign AnimatedPadding AnimatedPositioned AnimatedCrossFade AnimatedSize AnimatedScale
AnimatedSlide AnimatedRotation Curve Curves Duration Future Stream List Map Set Iterable
Object Exception Error Function VoidCallback ValueChanged ValueNotifier ValueListenable
ValueListenableBuilder ChangeNotifier Listenable InheritedWidget InheritedModel
Semantics GestureDetector MouseRegion MouseCursor SystemMouseCursors PointerEvent
TapDownDetails GestureLongPressStartDetails Focus Shortcuts Actions Intent CallbackAction
CallbackShortcuts LogicalKeyboardKey HardwareKeyboard KeyEvent SingleActivator
BackdropFilter ImageFilter ImageFiltered ShaderMask BlendMode Paint CustomPainter CustomPaint
Canvas Path RRect Matrix4 Transform Opacity Card Chip CircleAvatar Divider ListTile ListView
GridView SliverGridDelegate SliverGridDelegateWithFixedCrossAxisCount IconButton TextButton
ElevatedButton OutlinedButton FilledButton FloatingActionButton Switch Checkbox Radio Slider
TextField TextFormField InputDecoration Form FormState Tooltip PopupMenuButton PopupMenuItem
PopupMenuDivider PopupMenuEntry showMenu showDialog showModalBottomSheet AlertDialog
Dialog RouteSettings ButtonStyle RoundedRectangleBorder StadiumBorder CircleBorder ShapeBorder
OutlinedBorder RefreshIndicator LinearProgressIndicator CircularProgressIndicator
NavigationBar NavigationRail NavigationDestination NavigationRailDestination
NavigationRailLabelType NavigationBarLabelBehavior TabBar TabBarView TabController Tab
DefaultTabController SingleChildScrollView Padding SizedBox Expanded Flexible Spacer Column
Row Stack Positioned Wrap Container Center Align AspectRatio FractionallySizedBox
IntrinsicHeight IntrinsicWidth FittedBox OverflowBox LimitedBox ConstrainedBox DecoratedBox
UnconstrainedBox Baseline IndexedStack Offstage Visibility LayoutBuilder Builder
NullableIndexedWidgetBuilder IndexedWidgetBuilder ScrollNotification NotificationListener
ScrollMetrics ScrollPosition Axis CrossAxisAlignment MainAxisAlignment MainAxisSize
HitTestBehavior BoxShape BoxBorder Border BorderSide Radius RelativeRect RenderBox Overlay
Material InkWell Ink IgnorePointer SafeArea Hero FadeTransition ScaleTransition SlideTransition
FlexibleSpaceBar RichText Table TableRow DataTable ExpansionTile NestedScrollView
TextInputType TextInputAction Brightness SystemUiOverlayStyle Locale Localizations
WidgetsBinding WidgetsBindingObserver SchedulerBinding
AsyncValue AsyncNotifier Notifier ProviderContainer ProviderScope StateNotifier Consumer
ConsumerWidget ConsumerState ConsumerStatefulWidget WidgetRef TickerProvider
SingleTickerProviderStateMixin DateTime Duration FormatException ArgumentError
Platform SocketException MapEntry Completer Timer Stopwatch Random RegExp Match
PageTransitionsBuilder PageTransitionsTheme ThemeMode
z Dio DioException BaseOptions ResponseType LaunchMode
""".split()
)

CARET = {
    "fail": "\033[31m[FAIL]\033[0m",
    "warn": "\033[33m[WARN]\033[0m",
    "ok": "\033[32m[ OK ]\033[0m",
    "info": "\033[36m[INFO]\033[0m",
}


def colorize(key: str) -> str:
    if os.name == "nt" and not os.environ.get("WT_SESSION"):
        return {"fail": "[FAIL]", "warn": "[WARN]", "ok": "[ OK ]", "info": "[INFO]"}[key]
    return CARET[key]


# ── 工具函数 ────────────────────────────────────────────────────────

def read_sources() -> dict[str, str]:
    """返回 {相对于 lib 的 POSIX 路径: 源码}。"""
    out: dict[str, str] = {}
    for dirpath, _dirnames, filenames in os.walk(LIB_ROOT):
        for name in filenames:
            if not name.endswith(".dart"):
                continue
            full = os.path.join(dirpath, name)
            with open(full, "r", encoding="utf-8") as fh:
                out[os.path.relpath(full, LIB_ROOT).replace("\\", "/")] = fh.read()
    return out


def strip_strings_and_comments(src: str) -> str:
    """粗粒度剔除字符串与注释，降低误判。"""
    src = re.sub(r"'''.*?'''", "''", src, flags=re.S)
    src = re.sub(r'""".*?"""', '""', src, flags=re.S)
    src = re.sub(r"//[^\n]*", "", src)
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    return src


def balanced(src: str, opener: str, closer: str) -> bool:
    return src.count(opener) == src.count(closer)


def match_pair(s: str, i: int, opener: str, closer: str) -> int:
    """从 s[i] == opener 起找到配对 closer 的下标；失败返回 -1。"""
    depth = 0
    while i < len(s):
        if s[i] == opener:
            depth += 1
        elif s[i] == closer:
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def split_top_level(argstr: str) -> list[str]:
    parts, depth, cur = [], 0, []
    for ch in argstr:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    if "".join(cur).strip():
        parts.append("".join(cur))
    return parts


IMPORT_RE = re.compile(r"""^\s*(?:import|export)\s+'([^']+)'\s*(?:as\s+(\w+))?\s*;""", re.M)
# 仅匹配 import（用于「未使用 import」检查，export 是 barrel 文件的正常写法）
IMPORT_ONLY_RE = re.compile(r"""^\s*import\s+'([^']+)'\s*(?:as\s+(\w+))?\s*;""", re.M)
CLASS_RE = re.compile(r"\b(?:sealed\s+|abstract\s+|final\s+|base\s+)?(?:class|enum|extension|mixin)\s+(\w+)")
CTOR_DECL_RE = re.compile(r"(?:const\s+)?\b(\w+)(?:\.(\w+))?\s*\(")

# 顶层函数声明：`^<返回类型> <name>[(<泛型>)] (...)` 后面跟着 `{` 或 `=>`。
# 行首锚定 `^` 是关键——类内方法都有缩进，因此不会被误捕。
# 之所以要单独识别：`Future<bool> showConfirmDialog(...)` 这类顶层函数
# 也是文件对外的公开符号，漏掉会让「未使用 import」整条规则误报。
# 泛型参数列表 `<T>` 必须显式允许：`Future<T?> showPlayerSideSheet<T>(...)`
# 这种带类型参数的顶层函数在项目里很常见，漏掉同样会导致误报。
TOP_FUNCTION_RE = re.compile(
    r"^[A-Za-z_][\w<>,\s\.\?\[\]]*?\s+(\w+)\s*(?:<[^>{}()]{0,80}>)?\s*"
    r"\([^;]{0,800}?\)\s*(?:async\s*)?(?:=>|\{)",
    re.M | re.S,
)


def extract_params(param_str: str) -> set[str]:
    """从形参串中提取参数名，支持位置参数 + {命名} + [可选位置] 混排。"""
    names: set[str] = set()
    positional: list[str] = []
    blocks: list[str] = []
    i = 0
    while i < len(param_str):
        ch = param_str[i]
        if ch in "{[":
            close = match_pair(param_str, i, ch, "}" if ch == "{" else "]")
            if close > 0:
                blocks.append(param_str[i + 1:close])
                i = close + 1
                continue
        positional.append(ch)
        i += 1

    for segment in ["".join(positional), *blocks]:
        for part in split_top_level(segment):
            part = part.strip()
            if not part:
                continue
            part = re.sub(r"^\s*(?:required\s+|covariant\s+|final\s+|const\s+)+", "", part)
            m = re.match(r"^(?:this\.|super\.)(\w+)", part)
            if m:
                names.add(m.group(1))
                continue
            m = re.match(r"^[\w<>,\s\.\?\[\]]+?\s(\w+)\s*(?:=|$)", part)
            if m:
                names.add(m.group(1))
    return names


# ── 检查项 ──────────────────────────────────────────────────────────

def check_import_paths(srcs: dict[str, str]) -> int:
    print("\n── A. 相对 import/export 路径可解析性 ──")
    problems = 0
    for rel, src in sorted(srcs.items()):
        for m in IMPORT_RE.finditer(src):
            target = m.group(1)
            if target.startswith(("dart:", "package:")):
                continue
            resolved = os.path.normpath(
                os.path.join(LIB_ROOT, os.path.dirname(rel), target)
            )
            if not os.path.isfile(resolved):
                print(f"{colorize('fail')} {rel}")
                print(f"        import '{target}' -> 不存在")
                problems += 1
    print(f"{colorize('ok') if not problems else colorize('fail')} "
          f"{len(srcs)} 个文件，问题 {problems} 处")
    return problems


EXPORT_RE = re.compile(r"""^\s*export\s+'([^']+)'\s*;""", re.M)


def build_exports(
    srcs: dict[str, str],
    include_functions: bool = True,
) -> dict[str, set[str]]:
    """计算每个文件对外暴露的公开符号，**穿透 barrel 文件的 re-export**。

    [include_functions] 为 False 时只统计类型与顶层变量。G（死代码）用它把
    范围限定在"公开类型"，避免把 `main()` 这类入口函数也算成死代码。
    """
    own: dict[str, set[str]] = {}
    # 每个文件显式导出的类 / 顶层变量
    for rel, src in srcs.items():
        clean = strip_strings_and_comments(src)
        syms = set(re.findall(
            r"^(?:sealed\s+|abstract\s+|final\s+|base\s+)?(?:class|enum|extension|mixin|typedef)\s+(\w+)",
            clean, re.M))
        syms |= set(re.findall(r"^(?:final|const|var|late)\s+[\w<>,\s\.\?\[\]]*?\b(\w+)\s*=", clean, re.M))
        if include_functions:
            syms |= set(TOP_FUNCTION_RE.findall(clean))
        own[rel] = {s for s in syms if not s.startswith("_")}

    memo: dict[str, set[str]] = {}
    visiting: set[str] = set()

    def resolve(rel: str) -> set[str]:
        if rel in memo:
            return memo[rel]
        if rel in visiting:  # 环形 re-export 保护
            return set()
        visiting.add(rel)
        result = set(own.get(rel, set()))
        for m in EXPORT_RE.finditer(srcs.get(rel, "")):
            target = m.group(1)
            if target.startswith(("dart:", "package:")):
                continue
            resolved = os.path.normpath(os.path.join(LIB_ROOT, os.path.dirname(rel), target))
            rel_target = os.path.relpath(resolved, LIB_ROOT).replace("\\", "/")
            if rel_target in srcs:
                result |= resolve(rel_target)
        visiting.discard(rel)
        memo[rel] = result
        return result

    for rel in srcs:
        resolve(rel)
    return memo


def check_unused_imports(srcs: dict[str, str]) -> int:
    print("\n── B. 未使用的相对 import ──")
    exports = build_exports(srcs)
    problems = 0
    for rel in sorted(srcs):
        src = srcs[rel]
        body = set(re.findall(r"\b\w+\b", strip_strings_and_comments(IMPORT_RE.sub("", src))))
        for m in IMPORT_ONLY_RE.finditer(src):
            target, alias = m.group(1), m.group(2)
            if target.startswith(("dart:", "package:")):
                continue
            resolved = os.path.normpath(os.path.join(LIB_ROOT, os.path.dirname(rel), target))
            rel_target = os.path.relpath(resolved, LIB_ROOT).replace("\\", "/")
            exp = exports.get(rel_target)
            if exp is None:
                continue
            used = alias in body if alias else bool(exp & body)
            if not used:
                print(f"{colorize('warn')} {rel}: import '{target}' 未被使用")
                problems += 1
    print(f"{colorize('ok') if not problems else colorize('warn')} 问题 {problems} 处")
    return problems


TOKEN_FILES = {
    "AppColors": "core/design/app_colors.dart",
    "AppSpacing": "core/design/app_spacing.dart",
    "AppRadius": "core/design/app_spacing.dart",
    "AppStroke": "core/design/app_spacing.dart",
    "AppSizes": "core/design/app_spacing.dart",
    "AppShadows": "core/design/app_shadows.dart",
    "AppMotion": "core/design/app_motion.dart",
    "AppLayout": "core/design/app_layout.dart",
    "AppLayoutData": "core/design/app_layout.dart",
    "AppTransition": "core/design/app_motion.dart",
    "AppTypography": "core/design/app_typography.dart",
}


def check_design_tokens(srcs: dict[str, str]) -> int:
    print("\n── C. 设计令牌成员引用 ──")
    joined = "\n".join(srcs.values())
    problems = 0
    for cls, rel in TOKEN_FILES.items():
        body = srcs.get(rel)
        if body is None:
            print(f"{colorize('fail')} 令牌文件缺失: {rel}")
            problems += 1
            continue
        tokens = set(re.findall(r"\b\w+\b", body))
        refs = sorted(set(re.findall(r"\b%s\.(\w+)" % cls, joined)))
        bad = [r for r in refs if r not in tokens and r != "_"]
        if bad:
            for b in bad:
                print(f"{colorize('fail')} {cls}.{b} 未在 {rel} 中定义")
                problems += 1
    print(f"{colorize('ok') if not problems else colorize('fail')} 问题 {problems} 处")
    return problems


def check_providers(srcs: dict[str, str]) -> int:
    print("\n── D. Provider 标识符定义完整性 ──")
    joined = "\n".join(srcs.values())
    defined = set(re.findall(r"\b(\w+Provider)\s*=", joined))
    used = set(re.findall(r"\b(\w+Provider)\b", joined))
    sdk = {
        "Provider", "StateProvider", "StreamProvider", "FutureProvider", "NotifierProvider",
        "AsyncNotifierProvider", "StateNotifierProvider", "ChangeNotifierProvider",
        "ProviderFamily", "StateProviderFamily", "FutureProviderFamily",
        "AutoDisposeProvider", "AutoDisposeStateProvider", "AutoDisposeFutureProvider",
        "AutoDisposeStreamProvider", "AutoDisposeAsyncNotifierProvider", "Family",
    }
    missing = sorted(used - defined - sdk)
    for name in missing:
        print(f"{colorize('fail')} {name} 被引用但未定义")
    print(f"{colorize('ok') if not missing else colorize('fail')} 问题 {len(missing)} 处")
    return len(missing)


def collect_ctors(srcs: dict[str, str]) -> dict[str, set[str]]:
    ctors: dict[str, set[str]] = {}
    for src in srcs.values():
        for cm in CLASS_RE.finditer(src):
            cname = cm.group(1)
            brace = src.find("{", cm.end())
            if brace < 0:
                continue
            end = match_pair(src, brace, "{", "}")
            if end < 0:
                continue
            body = src[brace + 1:end]
            for ctor_m in CTOR_DECL_RE.finditer(body):
                if ctor_m.group(1) != cname:
                    continue
                popen = body.index("(", ctor_m.start())
                pclose = match_pair(body, popen, "(", ")")
                if pclose < 0:
                    continue
                ctors.setdefault(cname, set()).update(extract_params(body[popen + 1:pclose]))
    return ctors


def check_ctor_args(srcs: dict[str, str]) -> int:
    print("\n── E. 构造调用实参一致性 ──")
    ctors = collect_ctors(srcs)
    problems = checked = 0
    for rel, src in sorted(srcs.items()):
        for cm in re.finditer(r"\b(\w+)\s*\(", src):
            cname = cm.group(1)
            if cname not in ctors:
                continue
            tail = src[max(0, cm.start() - 70):cm.start()]
            if re.search(r"(?:const|static|factory|@override|\bclass)\s*$", tail) and "=" not in tail:
                continue
            popen = cm.end() - 1
            pclose = match_pair(src, popen, "(", ")")
            if pclose < 0:
                continue
            named = [
                m.group(1)
                for m in (re.match(r"^\s*(\w+)\s*:", a) for a in split_top_level(src[popen + 1:pclose]))
                if m
            ]
            if not named:
                continue
            checked += 1
            bad = [n for n in named if n not in ctors[cname]]
            if bad:
                print(f"{colorize('fail')} {rel}: {cname}(...) 未定义参数 {', '.join(bad)}")
                print(f"        可用: {', '.join(sorted(ctors[cname]))}")
                problems += 1
    print(f"{colorize('ok') if not problems else colorize('fail')} "
          f"校验 {checked} 处调用，问题 {problems} 处")
    return problems


KEY_CLASSES = [
    "AppRoutes", "PosterGridMetrics", "HomeFeedService", "AppMenu", "AppScaffoldInsets",
    "SourceManager", "SearchAggregator", "TitleNormalizer", "JsonPath", "IdGenerator",
    "Semaphore", "HtmlUtils",
]


def check_members(srcs: dict[str, str]) -> int:
    print("\n── F. 命名构造函数 / 关键类成员 ──")
    joined = "\n".join(srcs.values())
    bodies: dict[str, str] = {}
    for src in srcs.values():
        for m in CLASS_RE.finditer(src):
            brace = src.find("{", m.end())
            if brace < 0:
                continue
            end = match_pair(src, brace, "{", "}")
            bodies[m.group(1)] = src[brace + 1:end] if end > 0 else ""

    problems = 0
    for rel, src in sorted(srcs.items()):
        for m in re.finditer(r"\b(\w+)\.(\w+)\s*\(", src):
            cls, member = m.group(1), m.group(2)
            body = bodies.get(cls)
            if body is None or member in {
                "length", "toString", "runtimeType", "keys", "values", "first", "last",
                "indexOf", "contains", "join", "map", "where", "add", "addAll", "forEach",
                "any", "every", "isEmpty", "isNotEmpty", "toList", "toSet", "sublist",
            }:
                continue
            if not re.search(r"\b%s\b" % re.escape(member), body):
                print(f"{colorize('fail')} {rel}: {cls}.{member} 在该类中不存在")
                problems += 1

    print(f"{colorize('ok')} 命名成员检查完成" if not problems else f"{colorize('fail')} 问题 {problems} 处")
    return problems


def check_dead_types(srcs: dict[str, str], quiet: bool = True) -> int:
    print("\n── G. 死代码（定义但从未引用的公开类型） ──")
    joined = "\n".join(srcs.values())
    exports = build_exports(srcs, include_functions=False)
    dead = []
    for rel, syms in exports.items():
        for name in syms:
            uses = len(re.findall(r"\b%s\b" % re.escape(name), joined))
            if uses <= 1:
                dead.append((name, rel))
    for name, rel in dead:
        tag = colorize("info") if name in SDK_TYPES else colorize("warn")
        print(f"{tag} {name}  (定义于 {rel}，全项目仅出现 1 次)")
    print(f"{colorize('ok')} 疑似死代码 {len(dead)} 个（扩展方法/注解类会误报，需人工确认）")
    return 0  # 死代码只提示，不阻断


def main() -> int:
    if not os.path.isdir(LIB_ROOT):
        print(f"找不到 lib 目录: {LIB_ROOT}")
        return 1
    srcs = read_sources()
    print(f"MovieHub 结构静态校验 · {len(srcs)} 个 Dart 文件 · {LIB_ROOT}")

    total = 0
    total += check_import_paths(srcs)
    total += check_unused_imports(srcs)
    total += check_design_tokens(srcs)
    total += check_providers(srcs)
    total += check_ctor_args(srcs)
    total += check_members(srcs)
    check_dead_types(srcs)

    print("\n" + "=" * 52)
    if total == 0:
        print(colorize("ok") + " 全部结构校验通过。")
        print("提示：仍需运行 `flutter analyze` 做类型级校验。")
    else:
        print(colorize("fail") + f" 共 {total} 处结构问题，请修复后重跑。")
    print("=" * 52)
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
