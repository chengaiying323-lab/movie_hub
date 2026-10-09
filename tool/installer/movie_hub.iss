; =============================================================================
; MovieHub · Windows 安装包（Inno Setup 6）
; =============================================================================
;
; 编译方式（不要直接双击 .iss，本脚本依赖外部传入的变量）
; -----------------------------------------------------------------------------
;   推荐：走一键脚本
;       powershell -ExecutionPolicy Bypass -File tool/package_windows.ps1 -Installer
;
;   手动：
;       ISCC.exe /DAppVersion=1.0.0 /DSourceDir=<便携版目录> /O<输出目录> movie_hub.iss
;
;   AppVersion / SourceDir 都可以不传，会回落到下面的默认值。
;
; 编码说明
; -----------------------------------------------------------------------------
; 本文件是 **UTF-8 with BOM**。Inno Setup 6 在无 BOM 时会按系统 ANSI 代码页
; 解析，中文会变乱码。若你用编辑器改了本文件，请确保保存为"UTF-8 带 BOM"。
;
; 关于界面语言
; -----------------------------------------------------------------------------
; Inno Setup 官方**不包含**简体中文语言文件（Languages\ 下只有英法德日等），
; 中文包在社区的 "Unofficial Languages" 里。为了"零外部依赖、开箱即编译"，
; 这里以 Default.isl（英文）为基底，再用 [Messages] 覆盖最常看到的那些文案。
; 若想彻底中文化，去下载 ChineseSimplified.isl 放进 Inno 的 Languages 目录，
; 然后加一行：#define ChineseAvailable 1 并取消下面 [Languages] 的注释。
; =============================================================================

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

; 默认指向 package_windows.ps1 产出的便携版目录。
; 用相对路径时以本 .iss 所在目录为基准。
#ifndef SourceDir
  #define SourceDir "..\..\dist\movie_hub-1.0.0-windows-x64-portable"
#endif

#define AppName        "MovieHub"
#define AppPublisher   "MovieHub"
#define AppExeName     "movie_hub.exe"

[Setup]
; AppId 是本应用的唯一标识，升级安装/卸载都靠它匹配。
; 一旦发布就不要再改，否则老版本无法被新版本覆盖安装。
AppId={{2E4B7A19-3C6D-4F58-9A02-1D8E5C7B4A63}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
VersionInfoVersion={#AppVersion}
VersionInfoDescription={#AppName} 安装程序

; lowest + OverridesAllowed=dialog：默认「仅为我安装」，用户可在向导里改成全机安装。
; 这样默认不弹 UAC，对自用/便携场景更顺。
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
; 上一行关掉了"选择开始菜单文件夹"页，让向导更短

; x64：Flutter 的 Windows 产物是 64 位，装到 32 位目录会显得很怪。
; 注：Inno Setup 6.3+ 会建议改用 x64compatible（语义更精确），
; 两种写法都能编译，这里选兼容面更广的 x64。
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64

; Flutter 的 Windows 后端要求 Windows 10 1809 (17763) 及以上
MinVersion=10.0.17763

; 单文件安装包，最大压缩（安装时多花一点时间换更小的分发体积）
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern

; 若程序正在运行，安装前提示关闭；配合 [Files] 里的 restartreplace
CloseApplications=yes
RestartApplications=no

OutputDir=.
OutputBaseFilename=movie_hub-{#AppVersion}-windows-x64-setup

; 有 .ico 时打开这一行（仓库当前不带图标，故注释掉）
; SetupIconFile=..\..\windows\runner\resources\app_icon.ico

UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExeName}

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
; 装了社区中文语言包后，注释掉上面那行、启用下面这行：
; Name: "zh"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加任务："
Name: "quicklaunchicon"; Description: "创建快速启动栏快捷方式"; GroupDescription: "附加任务："; Flags: unchecked

[Files]
; 整个 Release 目录平铺进 {app}：
;   movie_hub.exe / flutter_windows.dll / libmpv-2.dll / data\ ...
; 这些文件的相对位置由 Flutter 写死在 exe 里，**不能重新组织目录结构**。
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs restartreplace
Source: "{#SourceDir}\使用说明.txt"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}";  Filename: "{app}\{#AppExeName}"; Tasks: desktopicon
Name: "{userappdata}\Microsoft\Internet Explorer\Quick Launch\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: quicklaunchicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "立即运行 {#AppName}"; Flags: nowait postinstall skipifsilent

; ─────────────────────────────────────────────────────────────────────────────
; 可选：注册 moviehub:// 自定义协议，用于「点链接导入订阅」。
; 需要客户端侧配合（Windows 上要读注册表拿到启动参数），当前版本未实现，
; 因此默认注释掉，留作后续阶段的接线点。
;
; [Registry]
; Root: HKA; Subkey: "Software\Classes\moviehub"; ValueType: string; ValueName: ""; ValueData: "URL:MovieHub 订阅链接"; Flags: uninsdeletekey
; Root: HKA; Subkey: "Software\Classes\moviehub"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
; Root: HKA; Subkey: "Software\Classes\moviehub\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#AppExeName},0"
; Root: HKA; Subkey: "Software\Classes\moviehub\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExeName}"" ""%1"""
; ─────────────────────────────────────────────────────────────────────────────

[Code]
{ ---------------------------------------------------------------------------
  运行库预检
  ---------------------------------------------------------------------------
  Flutter 的 Windows 产物动态链接 MSVC 运行库（/MD）。目标机缺少
  VC++ 2015-2022 Redistributable (x64) 时的表现是「双击没反应」——
  没有任何对话框、事件日志里也难找，是最劝退的一类问题。
  这里在安装前主动提示，并且只警告不阻拦（运行库也可能由其它软件已安装）。

  用注册表判定而不是找 vcruntime140.dll 文件：
  安装程序是 32 位进程，访问 System32 会被 WOW64 重定向到 SysWOW64，
  在那里找 64 位运行库必然找不到 —— 这是个很容易写错的坑。
  --------------------------------------------------------------------------- }
function IsVCRedistX64Installed(): Boolean;
var
  Installed: Cardinal;
begin
  Result := RegQueryDWordValue(
              HKLM64,
              'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64',
              'Installed',
              Installed) and (Installed = 1);
end;

function InitializeSetup(): Boolean;
begin
  Result := True;
  if not IsVCRedistX64Installed() then
  begin
    if MsgBox(
         '未检测到 Microsoft Visual C++ 2015-2022 运行库 (x64)。' + #13#10 + #13#10 +
         '缺少该运行库时，程序启动会没有任何反应。' + #13#10 +
         '建议先安装：https://aka.ms/vs/17/release/vc_redist.x64.exe' + #13#10 + #13#10 +
         '是否仍要继续安装？',
         mbConfirmation, MB_YESNO) = IDNO then
      Result := False;
  end;
end;

[Messages]
; 中文界面覆盖。基座是英文的 Default.isl，这里替换掉向导里最常出现的文案。
; 如果 ISCC 报 "Unknown message name"，删掉对应那一行即可 ——
; 不同 Inno 版本的消息集合略有出入。
SetupAppTitle=安装向导
SetupWindowTitle=安装 - %1
WelcomeLabel1=欢迎使用 %1 安装向导
WelcomeLabel2=即将在你的电脑上安装 %1。%n%n建议在继续前关闭其它正在运行的程序。
SelectDirLabel3=安装程序将把 %1 安装到以下文件夹。
SelectDirBrowseLabel=点击"下一步"继续。如需更换文件夹，点击"浏览"。
DiskSpaceMBLabel=至少需要 %1 MB 可用磁盘空间。
ReadyLabel1=安装程序已准备好开始安装 %1。
ReadyLabel2a=点击"安装"开始安装；如需检查或更改设置，点击"上一步"。
InstallingLabel=正在安装 %1，请稍候…
FinishedLabel=安装完成。%n%n%1 已安装到你的电脑上。
FinishedLabelNoIcons=安装完成。%n%n%1 已安装到你的电脑上。
ClickFinish=点击"完成"结束安装向导。
ButtonNext=下一步(&N) >
ButtonBack=< 上一步(&B)
ButtonInstall=安装(&I)
ButtonFinish=完成(&F)
ButtonBrowse=浏览(&R)…
ButtonCancel=取消
UninstallAppFullTitle=卸载 %1
ConfirmUninstall=确定要完全卸载 %1 及其所有组件吗？
UninstalledAll=%1 已成功从你的电脑上卸载。
