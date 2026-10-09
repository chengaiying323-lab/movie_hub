#Requires -Version 5.1
<#
.SYNOPSIS
    生成 MovieHub 的平台脚手架（ios / windows）。

.DESCRIPTION
    本仓库是"先写业务代码、后补平台目录"的形态——`lib/` 已经完整，
    但 `ios/`、`windows/` 还没生成。Flutter 的官方做法就是用
    `flutter create --platforms=... .` 在既有工程上补平台目录，
    它**只补平台侧文件，不会碰 `lib/`**。

    生成本脚本的两个原因：
    1. 少打错字。手敲 `flutter create` 的参数（`--org`、`--project-name`）
       一旦写错，Bundle ID / 应用 ID 就要在生成后到处改。
    2. 生成完立刻跑 iOS 补丁。否则 `ios/` 是"半成品"状态——
       最低版本还是 12.0、ATS 也没开，第一次云端构建必然失败。

.PARAMETER Platforms
    要生成的平台，默认 ios + windows。

.PARAMETER Org
    反向域名前缀，决定 iOS Bundle ID 与 Windows 应用标识。
    默认 `com.moviehub` → iOS 得到 `com.moviehub.movieHub`。
    **注意：`--org` 只在首次生成时生效，之后再改要先删掉平台目录重生成。**

.PARAMETER Force
    平台目录已存在时也强制重新生成。
    警告：会覆盖 `ios/Runner/Info.plist`、`windows/runner/*.rc` 等模板文件，
    你对这些文件的本地修改会丢失。默认关闭。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tool/scaffold_platforms.ps1
    powershell -ExecutionPolicy Bypass -File tool/scaffold_platforms.ps1 -Org com.yourname
#>
[CmdletBinding()]
param(
    [string[]]$Platforms = @('ios', 'windows'),
    [string]$Org = 'com.moviehub',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ── 定位项目根目录（本脚本在 tool/ 下） ─────────────────────────────────────
$Root = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $Root 'pubspec.yaml'))) {
    throw "未找到 pubspec.yaml —— 脚本应位于 <项目根>/tool/ 目录下。当前解析到：$Root"
}

function Write-Step([string]$Text) { Write-Host "`n▶ $Text" -ForegroundColor Cyan }
function Write-Ok([string]$Text)   { Write-Host "  ✔ $Text" -ForegroundColor Green }
function Write-Warn2([string]$Text) { Write-Host "  ! $Text" -ForegroundColor Yellow }

Write-Host "MovieHub · 平台脚手架生成" -ForegroundColor Magenta
Write-Host "项目根目录：$Root"

# ── 检查 Flutter ───────────────────────────────────────────────────────────
Write-Step '检查 Flutter 工具链'
$flutter = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutter) {
    throw "未找到 flutter 命令。请先安装 Flutter SDK 并把 <flutter>/bin 加入 PATH。"
}
Write-Ok "flutter → $($flutter.Source)"
& flutter --version
if ($LASTEXITCODE -ne 0) { throw 'flutter --version 执行失败' }

# ── 判断是否需要生成 ───────────────────────────────────────────────────────
Write-Step '检查平台目录状态'
$missing = @()
foreach ($p in $Platforms) {
    $dir = Join-Path $Root $p
    if (Test-Path $dir) {
        if ($Force) {
            Write-Warn2 "$p/ 已存在，-Force 已指定 → 将重新生成（本地修改会丢失）"
        } else {
            Write-Ok "$p/ 已存在，跳过（要重建请加 -Force）"
        }
    } else {
        Write-Warn2 "$p/ 不存在，需要生成"
        $missing += $p
    }
}

if ($missing.Count -eq 0) {
    Write-Host "`n所有平台目录都已存在，无需生成。" -ForegroundColor Green
} else {
    Write-Step "生成平台目录：$($missing -join ', ')"
    Push-Location $Root
    try {
        # --project-name 必须与 pubspec.yaml 的 name 一致，否则生成的应用名会错。
        # --platforms 只列出缺失的，避免顺手重建已有平台。
        $args = @(
            'create',
            '--platforms', ($missing -join ','),
            '--org', $Org,
            '--project-name', 'movie_hub',
            '.'
        )
        Write-Host "  flutter $($args -join ' ')" -ForegroundColor DarkGray
        & flutter @args
        if ($LASTEXITCODE -ne 0) { throw "flutter create 失败（退出码 $LASTEXITCODE）" }
        Write-Ok '平台目录生成完成'
    } finally {
        Pop-Location
    }
}

# ── 生成后立刻补 iOS 配置 ─────────────────────────────────────────────────
if ($Platforms -contains 'ios') {
    $iosInfo = Join-Path $Root 'ios/Runner/Info.plist'
    if (Test-Path $iosInfo) {
        Write-Step '应用 iOS 工程补丁（最低版本 / ATS / 后台模式 / 旋转）'
        $py = Get-Command python -ErrorAction SilentlyContinue
        if ($py) {
            & python (Join-Path $PSScriptRoot 'patch_ios_project.py') '--print'
            if ($LASTEXITCODE -ne 0) {
                Write-Warn2 'iOS 补丁脚本执行失败，请手动检查（见 docs/BUILD_AND_RELEASE.md）'
            } else {
                Write-Ok 'iOS 配置已补齐'
            }
        } else {
            Write-Warn2 '未找到 python，无法自动补 iOS 配置。请手动执行：python tool/patch_ios_project.py'
        }
    }
}

# ── 收尾提示 ───────────────────────────────────────────────────────────────
Write-Host "`n──────────────── 下一步 ────────────────" -ForegroundColor Magenta
Write-Host @"
1. 确认生成结果： git status
2. 把平台目录提交进 Git —— 云端构建（GitHub Actions）依赖仓库里的 ios/：
       git add ios windows .github tool docs
       git commit -m "chore: 补齐 ios/windows 平台脚手架与打包配置"
3. 本地跑一次 Windows 打包验证工具链：
       powershell -ExecutionPolicy Bypass -File tool/package_windows.ps1

完整流程见 docs/BUILD_AND_RELEASE.md
"@ -ForegroundColor Gray
