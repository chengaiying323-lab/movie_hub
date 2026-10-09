#Requires -Version 5.1
<#
.SYNOPSIS
    MovieHub · Windows 桌面端一键打包（便携版 zip / Inno Setup 安装包）。

.DESCRIPTION
    一条命令完成：pub get → flutter build windows --release → 便携版目录 → zip
    →（可选）Inno Setup 安装包。

    关于"便携版"的形态
    ----------------------------------------------------------------------
    Flutter Windows Release 产物**不是单个 exe**，而是一个目录：

        Release/
          movie_hub.exe              ← 启动器
          flutter_windows.dll        ← Flutter 引擎
          libmpv-2.dll               ← media_kit 的播放内核（体积最大）
          *.dll                      ← 各插件的原生库
          data/
            app.so                   ← Dart AOT 代码
            icudtl.dat
            flutter_assets/          ← 字体、图片、assets/sample/…

    所以"免安装便携版"的正确做法是把**整个 Release 目录**压成一个 zip，
    解压即用、可放 U 盘。要想做成真正的单文件，需要 MSIX 或自解压壳，
    对自用场景是纯粹的复杂度，本脚本不提供。

    目标机器的硬性依赖
    ----------------------------------------------------------------------
    需要 **Microsoft Visual C++ 2015-2022 可再发行组件 (x64)**。
    Flutter 的 Windows 模板默认动态链接 CRT（`/MD`），目标机没有这个运行库时
    表现是"双击没反应"或弹缺少 `VCRUNTIME140.dll` —— 这是便携版最常见的坑。
    让对方装一次即可，或改用 `-Installer` 出的安装包（安装包里有检测提示）。

.PARAMETER Mode
    构建模式，默认 release。

.PARAMETER Installer
    额外用 Inno Setup 生成单文件安装包。
    需要本机已安装 Inno Setup 6（脚本会自动找 ISCC.exe）。

.PARAMETER SkipBuild
    复用已有构建产物，只重新打包。改打包脚本时用这个避免重复编译。

.PARAMETER NoZip
    只产出便携版目录，不压缩成 zip。

.PARAMETER Clean
    编译前先 `flutter clean`（排查"改了代码但产物没变"这类诡异问题时用）。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tool/package_windows.ps1

.EXAMPLE
    # 出便携版 + 安装包，并先清理
    powershell -ExecutionPolicy Bypass -File tool/package_windows.ps1 -Clean -Installer
#>
[CmdletBinding()]
param(
    [ValidateSet('release', 'profile', 'debug')]
    [string]$Mode = 'release',

    [switch]$Installer,
    [switch]$SkipBuild,
    [switch]$NoZip,
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

# ── 基础工具 ───────────────────────────────────────────────────────────────
function Write-Step([string]$T) { Write-Host "`n▶ $T" -ForegroundColor Cyan }
function Write-Ok([string]$T)   { Write-Host "  ✔ $T" -ForegroundColor Green }
function Write-Note([string]$T) { Write-Host "  · $T" -ForegroundColor Gray }
function Write-Warn2([string]$T){ Write-Host "  ! $T" -ForegroundColor Yellow }

function Fail([string]$T) {
    Write-Host "`n  ✘ $T" -ForegroundColor Red
    exit 1
}

$Root = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $Root 'pubspec.yaml'))) {
    Fail "未找到 pubspec.yaml —— 脚本应位于 <项目根>/tool/ 下。当前解析到：$Root"
}

$DistDir = Join-Path $Root 'dist'

Write-Host "MovieHub · Windows 打包" -ForegroundColor Magenta
Write-Host "项目根目录：$Root"
Write-Host "构建模式  ：$Mode"

# ── 读版本号 ───────────────────────────────────────────────────────────────
Write-Step '读取应用版本'
$pubspecPath = Join-Path $Root 'pubspec.yaml'
$m = Select-String -Path $pubspecPath -Pattern '^version:\s*(.+)$' | Select-Object -First 1
if ($null -eq $m) { Fail "pubspec.yaml 里没找到 version: 行" }

$fullVersion = $m.Matches[0].Groups[1].Value.Trim()
# 文件名里不带 +build 号：`+` 在 URL / 部分工具链里需要转义，徒增麻烦。
$fileVersion = ($fullVersion -split '\+')[0]
Write-Ok "版本：$fullVersion （文件名用 $fileVersion）"

# ── 检查 Flutter ───────────────────────────────────────────────────────────
Write-Step '检查 Flutter 工具链'
$flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutterCmd) {
    Fail '未找到 flutter 命令。请安装 Flutter SDK 并把 <flutter>\bin 加入 PATH。'
}
Write-Ok "flutter → $($flutterCmd.Source)"

# 桌面端构建需要 Visual Studio 的 C++ 工具链，这里只做提示不做硬性拦截
# （`flutter doctor` 的输出格式随版本变动，不适合用来做判定）。
Write-Note '若编译报 "Unable to find suitable Visual Studio toolchain"，请运行 flutter doctor 查看详情'

# ── 清理 ───────────────────────────────────────────────────────────────────
if ($Clean -and -not $SkipBuild) {
    Write-Step 'flutter clean'
    Push-Location $Root; try { & flutter clean } finally { Pop-Location }
    if ($LASTEXITCODE -ne 0) { Fail 'flutter clean 失败' }
    Write-Ok '已清理'
}

# ── 依赖 ───────────────────────────────────────────────────────────────────
if (-not $SkipBuild) {
    Write-Step 'flutter pub get'
    Push-Location $Root; try { & flutter pub get } finally { Pop-Location }
    if ($LASTEXITCODE -ne 0) { Fail 'flutter pub get 失败' }
    Write-Ok '依赖就绪'
}

# ── 编译 ───────────────────────────────────────────────────────────────────
if (-not $SkipBuild) {
    Write-Step "flutter build windows --$Mode （这一步最慢，请耐心等待）"
    Push-Location $Root
    try {
        & flutter build windows "--$Mode"
    } finally {
        Pop-Location
    }
    if ($LASTEXITCODE -ne 0) { Fail "flutter build windows 失败（退出码 $LASTEXITCODE）" }
    Write-Ok '编译完成'
} else {
    Write-Note '-SkipBuild：复用已有产物'
}

# ── 定位产物目录 ───────────────────────────────────────────────────────────
Write-Step '定位构建产物'
$buildRoot = Join-Path $Root 'build\windows'
if (-not (Test-Path $buildRoot)) { Fail "构建目录不存在：$buildRoot（先去掉 -SkipBuild 跑一次完整构建）" }

$releaseCandidates = @()
foreach ($archDir in (Get-ChildItem -Path $buildRoot -Directory)) {
    $candidate = Join-Path $archDir.FullName 'runner\Release'
    if (Test-Path $candidate) { $releaseCandidates += $candidate }
}
if ($releaseCandidates.Count -eq 0) {
    Fail "在 $buildRoot 下没找到 runner\Release 目录，构建可能没真正产出"
}
$releaseDir = $releaseCandidates[0]
if ($releaseCandidates.Count -gt 1) {
    Write-Warn2 "发现多个架构产物：$($releaseCandidates -join ' | ')"
    Write-Warn2 "使用第一个：$releaseDir"
}
Write-Ok "产物目录：$releaseDir"

# ── 产物完整性校验 ─────────────────────────────────────────────────────────
# 这一步是"便携版能不能在别人电脑上跑起来"的关键。缺文件时打包出来能压，
# 但拷到目标机就是闪退，而且完全没有报错线索，所以在这里提前拦住。
Write-Step '校验产物完整性'

$exePath = Join-Path $releaseDir 'movie_hub.exe'
if (-not (Test-Path $exePath)) { Fail "缺少主程序 movie_hub.exe" }
Write-Ok 'movie_hub.exe'

$assetsDir = Join-Path $releaseDir 'data\flutter_assets'
if (-not (Test-Path $assetsDir)) { Fail "缺少 data\flutter_assets（assets/sample/ 等资源不会生效）" }
Write-Ok 'data\flutter_assets'

# libmpv：media_kit 的播放内核，由 media_kit_libs_windows_video 在构建时拷贝。
# 少了它，应用能启动、能浏览，但一点播放就崩 —— 最难排查的一类缺失。
$mpv = Get-ChildItem -Path $releaseDir -Filter 'libmpv*.dll' -ErrorAction SilentlyContinue
if ($null -eq $mpv) {
    Fail @"
缺少 libmpv-2.dll —— 播放功能会直接崩溃。
可能原因：pubspec.yaml 里没声明 media_kit_libs_windows_video，
或构建中途失败导致拷贝步骤被跳过。请检查依赖后重新完整构建。
"@
}
Write-Ok "播放内核：$($mpv[0].Name)"

$totalMB = [math]::Round(
    (Get-ChildItem -Path $releaseDir -Recurse -File | Measure-Object -Property Length -Sum).Sum / 1MB, 1)
Write-Ok "产物总大小：$totalMB MB"

# ── 便携版目录 ─────────────────────────────────────────────────────────────
$portableName = "movie_hub-$fileVersion-windows-x64-portable"
$portableDir  = Join-Path $DistDir $portableName

Write-Step "生成便携版目录：dist\$portableName"
if (-not (Test-Path $DistDir)) { New-Item -ItemType Directory -Path $DistDir | Out-Null }
if (Test-Path $portableDir) { Remove-Item -Path $portableDir -Recurse -Force }
Copy-Item -Path $releaseDir -Destination $portableDir -Recurse -Force
Write-Ok '已复制'

# 附带一份说明，避免"拷给朋友后对方不知道要先装 VC++ 运行库"
$readme = @"
MovieHub $fileVersion · Windows x64 便携版
================================================================

运行方式
    解压后双击 movie_hub.exe。无需安装，可放 U 盘。

运行前请确认
    已安装 Microsoft Visual C++ 2015-2022 可再发行组件 (x64)。
    下载：https://aka.ms/vs/17/release/vc_redist.x64.exe

    缺少该运行库时的表现是"双击没反应"或提示缺少 VCRUNTIME140.dll。

目录说明
    movie_hub.exe      主程序
    libmpv-2.dll       视频播放内核（不可删除）
    data\              程序资源（不可删除，也不可改名）

首次使用
    本程序不内置任何影视站点。启动后进入「数据源」页导入你自己的
    声明式 JSON 订阅；格式见仓库 docs/SOURCE_PROTOCOL.md。

合规声明
    本程序仅提供通用数据源的解析与播放框架，不含任何站点采集逻辑。
    请自行确保所导入数据源的合法性。
"@
$readmePath = Join-Path $portableDir '使用说明.txt'
# 用 UTF-8 **带 BOM** 写盘。带 BOM 时 Windows 记事本（含 1903 之前的老版本）、
# Notepad++、VS Code 都能正确识别中文。
#
# 这里刻意不用 GBK：`[System.Text.Encoding]::GetEncoding('GB2312')` 在
# PowerShell 7（.NET Core）下会抛 ArgumentException —— .NET Core 默认不注册
# CodePagesEncodingProvider，代码页 936 不可用。而 GitHub Actions 的
# windows-latest runner 用的正是 PowerShell 7，写 GBK 会让打包步骤直接失败。
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($readmePath, $readme, $utf8Bom)
Write-Ok '使用说明.txt'

# ── 压缩 ───────────────────────────────────────────────────────────────────
$zipPath = "$portableDir.zip"
if (-not $NoZip) {
    Write-Step '压缩为 zip'
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

    # 优先用 Windows 10 自带的 tar.exe（bsdtar）：
    # 比 Compress-Archive 快数倍，产出的 zip 也更标准
    # （Compress-Archive 打包大目录时又慢又容易出非标准条目）。
    $tarCmd = Get-Command tar.exe -ErrorAction SilentlyContinue
    if ($tarCmd) {
        Push-Location $DistDir
        try {
            & tar.exe -a -c -f "$portableName.zip" $portableName
        } finally {
            Pop-Location
        }
        if ($LASTEXITCODE -ne 0) { Write-Warn2 'tar 压缩失败，回退到 Compress-Archive' }
    }

    if (-not (Test-Path $zipPath)) {
        Compress-Archive -Path $portableDir -DestinationPath $zipPath -CompressionLevel Optimal -Force
    }

    if (Test-Path $zipPath) {
        $zipMB = [math]::Round((Get-Item $zipPath).Length / 1MB, 1)
        Write-Ok "dist\$portableName.zip （$zipMB MB）"
    } else {
        Fail '压缩失败'
    }
}

# ── Inno Setup 安装包 ──────────────────────────────────────────────────────
if ($Installer) {
    Write-Step '生成 Inno Setup 安装包'
    $issPath = Join-Path $PSScriptRoot 'installer\movie_hub.iss'
    if (-not (Test-Path $issPath)) { Fail "找不到安装包脚本：$issPath" }

    $iscc = $null
    $isccCmd = Get-Command iscc.exe -ErrorAction SilentlyContinue
    if ($isccCmd) {
        $iscc = $isccCmd.Source
    } else {
        $pf86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
        $pf   = [Environment]::GetEnvironmentVariable('ProgramFiles')
        $candidates = @()
        if ($pf86) { $candidates += (Join-Path $pf86 'Inno Setup 6\ISCC.exe') }
        if ($pf)   { $candidates += (Join-Path $pf   'Inno Setup 6\ISCC.exe') }
        if ($env:LOCALAPPDATA) { $candidates += (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe') }
        foreach ($c in $candidates) { if (Test-Path $c) { $iscc = $c; break } }
    }

    if (-not $iscc) {
        Write-Warn2 '未找到 ISCC.exe。请先安装 Inno Setup 6：https://jrsoftware.org/isdl.php'
        Write-Warn2 '安装后重跑本命令，或手动执行：'
        Write-Warn2 "  ISCC.exe /DAppVersion=$fileVersion /DSourceDir=$portableDir `"$issPath`""
    } else {
        Write-Ok "ISCC → $iscc"
        # /D 传入预处理器变量，让 .iss 不必硬编码路径；
        # /O 覆盖输出目录，产物直接落在 dist/。
        & $iscc "/DAppVersion=$fileVersion" "/DSourceDir=$portableDir" "/O$DistDir" $issPath
        if ($LASTEXITCODE -ne 0) {
            Write-Warn2 "ISCC 返回 $LASTEXITCODE，安装包可能未生成"
        } else {
            $setup = Get-ChildItem -Path $DistDir -Filter "*$fileVersion*setup*.exe" -ErrorAction SilentlyContinue |
                     Select-Object -First 1
            if ($setup) {
                $setupMB = [math]::Round($setup.Length / 1MB, 1)
                Write-Ok "dist\$($setup.Name) （$setupMB MB）"
            } else {
                Write-Ok '安装包已生成（请查看 dist/ 目录）'
            }
        }
    }
}

# ── 汇总 ───────────────────────────────────────────────────────────────────
Write-Host "`n════════════════ 打包完成 ════════════════" -ForegroundColor Green
Write-Host "  产品版本：$fullVersion"
Write-Host "  产物目录：$DistDir"
Write-Host "`n  dist/ 内容：" -ForegroundColor Cyan
Get-ChildItem -Path $DistDir | ForEach-Object {
    if ($_.PSIsContainer) {
        Write-Host ("    [目录] {0}" -f $_.Name) -ForegroundColor Gray
    } else {
        Write-Host ("    [文件] {0}  ({1} MB)" -f $_.Name, [math]::Round($_.Length / 1MB, 1)) -ForegroundColor Gray
    }
}
Write-Host @"

提醒
  · 便携版在**别人的电脑**上运行需要 VC++ 2015-2022 (x64) 运行库，
    目录里的「使用说明.txt」已写明这一点。
  · 首次打包后建议在干净的 Windows 环境实测一次解压即用。
"@ -ForegroundColor DarkGray
