# ============================================================
#  dsh-our-free-model 桌面端安装脚本
#  适用于 DSHEAC AIO / DeepSeek Harness 桌面端 / dsh web
#
#  按 README 桌面端规范安装（真实目录，不建 junction）：
#    1. 发布文件复制至 <profile>/node_modules/dsh-our-free-model/
#    2. dependencies 写入 "dsh-our-free-model": "<版本>"
#    3. dsh.profile.bundles 末尾追加 "dsh-our-free-model"
#  不改动 cordis.patch.yml（两处同时注册会报 duplicate loader entry）
#
#  用法：
#    powershell -NoProfile -ExecutionPolicy Bypass -File install-our-free-model.ps1
#    可选参数：
#      -DshHome   <路径>    指定 DSH_HOME（默认依次尝试 $env:DSH_HOME、~/.dsh、自动扫描）
#      -Profile   <名称>    指定 profile（默认依次尝试 web-desktop、desktop、web）
#      -Version   <版本>    指定插件版本（默认取发布清单的最新版）
#      -Uninstall           卸载（移除 bundle 条目、依赖条目与插件目录）
#      -NoPause             结束后不停留（供命令行调用）
# ============================================================
param(
    [string]$DshHome,
    [string]$Profile,
    [string]$Version,
    [switch]$Uninstall,
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$RepoOwner = 'Ebony-Vinyl'
$RepoName  = 'dsh-our-free-model'
$PluginId  = 'dsh-our-free-model'

# 下载源模板，{0}=ref，{1}=相对路径。按顺序尝试，成功后记住可用源
$Sources = @(
    'https://gh.liloususu.eu.cc/ebony-vinyl/dsh-our-free-model/raw/{0}/{1}',
    'https://ghfast.top/https://raw.githubusercontent.com/Ebony-Vinyl/dsh-our-free-model/{0}/{1}',
    'https://cdn.jsdelivr.net/gh/Ebony-Vinyl/dsh-our-free-model@{0}/{1}',
    'https://raw.githubusercontent.com/Ebony-Vinyl/dsh-our-free-model/{0}/{1}'
)

function Write-Step([string]$msg)  { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok([string]$msg)    { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Warn2([string]$msg) { Write-Host "  [!!] $msg" -ForegroundColor Yellow }
function Write-Bad([string]$msg)   { Write-Host "  [XX] $msg" -ForegroundColor Red }

function Test-ReparsePoint([string]$Path) {
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        return (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
    } catch { return $false }
}

# ---------- 下载（curl.exe 优先，Invoke-WebRequest 兜底） ----------
$Script:GoodSource = -1

function Invoke-Download {
    param([string]$Url, [string]$OutFile, [int]$TimeoutSec = 60)
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
        # curl 失败时向 stderr 写日志；EAP=Stop 会把它变成终止错误，需局部降级
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try { & $curl.Source -sSL --ssl-no-revoke --retry 1 -m $TimeoutSec -o $OutFile $Url 2>$null }
        finally { $ErrorActionPreference = $prevEap }
        if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $OutFile)) { return $true }
        Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
        return $false
    }
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -TimeoutSec $TimeoutSec -UseBasicParsing
        return $true
    } catch {
        Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
        return $false
    }
}

function Get-RepoFile {
    param([string]$Ref, [string]$RelPath, [string]$OutFile, [string]$ExpectSha256, [nullable[int]]$ExpectSize)
    # 已有同名暂存文件且哈希一致（断点续传）
    if ($ExpectSha256 -and (Test-Path -LiteralPath $OutFile)) {
        if ((Get-FileHash -LiteralPath $OutFile -Algorithm SHA256).Hash.ToLower() -eq $ExpectSha256) { return $true }
    }
    $order = @()
    if ($Script:GoodSource -ge 0) { $order += $Script:GoodSource }
    0..($Sources.Count - 1) | ForEach-Object { if ($order -notcontains $_) { $order += $_ } }
    foreach ($i in $order) {
        $url = $Sources[$i] -f $Ref, ($RelPath -replace '\\', '/')
        if (Invoke-Download -Url $url -OutFile $OutFile) {
            if ($ExpectSha256) {
                $got = (Get-FileHash -LiteralPath $OutFile -Algorithm SHA256).Hash.ToLower()
                if ($got -ne $ExpectSha256) { Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue; continue }
            }
            if ($ExpectSize -and (Get-Item -LiteralPath $OutFile).Length -ne $ExpectSize) {
                Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue; continue
            }
            $Script:GoodSource = $i
            return $true
        }
    }
    return $false
}

function Finish {
    param([int]$Code)
    if (-not $NoPause -and [Environment]::UserInteractive) {
        Write-Host ''
        Read-Host '按回车键退出' | Out-Null
    }
    exit $Code
}

Write-Host '=================================================' -ForegroundColor Cyan
Write-Host ' dsh-our-free-model 桌面端安装脚本' -ForegroundColor Cyan
Write-Host ' 免费 LLM 车道插件（真实目录方式，符合桌面端闸门）' -ForegroundColor Cyan
Write-Host '=================================================' -ForegroundColor Cyan

# ---------- 1. 定位 DSH_HOME ----------
Write-Step '定位 DSH_HOME（dsh 主目录）'
$home_ = $null
if ($DshHome) {
    $home_ = $DshHome
} elseif ($env:DSH_HOME -and (Test-Path (Join-Path $env:DSH_HOME 'profiles'))) {
    $home_ = $env:DSH_HOME
    Write-Ok "使用环境变量 DSH_HOME=$home_"
} elseif (Test-Path (Join-Path $env:USERPROFILE '.dsh\profiles')) {
    $home_ = Join-Path $env:USERPROFILE '.dsh'
    Write-Ok "使用默认位置 $home_"
} else {
    # 自动扫描常见位置：寻找包含 profiles\<name>\package.json 的目录
    Write-Warn2 '默认位置未找到，开始扫描常见安装位置…'
    $roots = @($env:USERPROFILE, $env:APPDATA, $env:LOCALAPPDATA) | Where-Object { $_ }
    foreach ($root in $roots) {
        Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $cand = Join-Path $_.FullName 'profiles'
            if (Test-Path $cand) {
                $hasProfile = Get-ChildItem -LiteralPath $cand -Directory -ErrorAction SilentlyContinue |
                    Where-Object { Test-Path (Join-Path $_.FullName 'package.json') }
                if ($hasProfile) { $home_ = $_.FullName }
            }
        }
        if ($home_) { break }
    }
    if ($home_) { Write-Ok "扫描到 $home_" }
}
if (-not $home_ -or -not (Test-Path (Join-Path $home_ 'profiles'))) {
    Write-Bad '未能定位 DSH_HOME（含 profiles 子目录的 dsh 主目录）。'
    Write-Host '  请先启动一次 dsh 桌面端以生成主目录，或用 -DshHome 参数手动指定。'
    Finish 1
}
$ProfilesRoot = Join-Path $home_ 'profiles'
Write-Host "  DSH_HOME = $home_"

# ---------- 2. 定位 profile ----------
Write-Step '定位 profile'
$profileDir = $null
if ($Profile) {
    $profileDir = Join-Path $ProfilesRoot $Profile
    if (-not (Test-Path (Join-Path $profileDir 'package.json'))) {
        Write-Bad "profile「$Profile」不存在或缺少 package.json：$profileDir"
        Write-Host '  请先启动一次桌面端以生成 profile。'
        Finish 1
    }
} else {
    foreach ($name in @('web-desktop', 'desktop', 'web')) {   # 桌面端优先
        $cand = Join-Path $ProfilesRoot $name
        if (Test-Path (Join-Path $cand 'package.json')) { $profileDir = $cand; break }
    }
    if (-not $profileDir) {
        $found = Get-ChildItem -LiteralPath $ProfilesRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { Test-Path (Join-Path $_.FullName 'package.json') } |
            Select-Object -ExpandProperty Name
        if ($found.Count -eq 1) {
            Write-Warn2 "未找到 web-desktop / desktop / web，使用唯一现有 profile「$($found[0])」"
            $profileDir = Join-Path $ProfilesRoot $found[0]
        } elseif ($found.Count -gt 1 -and [Environment]::UserInteractive) {
            Write-Host '  发现多个 profile：'
            for ($i = 0; $i -lt $found.Count; $i++) { Write-Host ("   [{0}] {1}" -f ($i + 1), $found[$i]) }
            $sel = Read-Host '请选择要安装到的 profile 序号'
            $idx = 0
            if ([int]::TryParse($sel, [ref]$idx) -and $idx -ge 1 -and $idx -le $found.Count) {
                $profileDir = Join-Path $ProfilesRoot $found[$idx - 1]
            }
        } elseif ($found.Count -gt 1) {
            Write-Bad ('发现多个 profile：' + ($found -join ', '))
            Write-Host '  请用 -Profile <名称> 指定。'
            Finish 1
        }
    }
}
if (-not $profileDir) {
    Write-Bad '未找到任何可用 profile。请先启动一次桌面端以生成 profile。'
    Finish 1
}
$ProfileName = Split-Path $profileDir -Leaf
Write-Ok "profile「$ProfileName」= $profileDir"

# ---------- 3. 获取发布清单 ----------
Write-Step '下载发布清单（feed/manifest.json，含全部文件 SHA-256）'
$StageRoot = Join-Path ([IO.Path]::GetTempPath()) "dsh-ofm-install-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
New-Item -ItemType Directory -Path $StageRoot -Force | Out-Null
$manifestPath = Join-Path $StageRoot 'feed-manifest.json'
if (-not (Get-RepoFile -Ref 'main' -RelPath 'feed/manifest.json' -OutFile $manifestPath)) {
    Write-Bad '所有下载源均无法获取发布清单。请检查网络后重试。'
    Write-Host '  可用源：gh.liloususu.eu.cc / ghfast.top / cdn.jsdelivr.net / raw.githubusercontent.com'
    Finish 1
}
try { $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch {
    Write-Bad '发布清单解析失败。'; Finish 1
}
if (-not $manifest.version -or -not $manifest.files) { Write-Bad '发布清单格式异常。'; Finish 1 }
$ver = if ($Version) { $Version } else { $manifest.version }
Write-Ok "插件版本 $ver（清单内 $($manifest.files.Count) 个文件）"
if ($Version -and $Version -ne $manifest.version) {
    Write-Warn2 "指定版本 $Version 与清单最新版 $($manifest.version) 不同，将按清单校验、按 v$Version 标签下载。"
}

# 文件下载 ref：优先 v标签，失败回退 main
$FileRef = "v$ver"
$probe = Join-Path $StageRoot 'probe.bin'
$refOk = $false
foreach ($i in 0..($Sources.Count - 1)) {
    $url = $Sources[$i] -f $FileRef, 'package.json'
    if (Invoke-Download -Url $url -OutFile $probe -TimeoutSec 30) { $refOk = $true; $Script:GoodSource = $i; break }
}
if ($refOk) { Write-Ok "使用标签 $FileRef 下载" } else { $FileRef = 'main'; Write-Warn2 "标签 v$ver 不可达，回退 main 分支（仍逐文件校验 SHA-256）" }
Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue

# ---------- 4. 逐文件下载并校验 ----------
Write-Step "下载并校验 $($manifest.files.Count) 个发布文件"
$idx = 0
foreach ($f in $manifest.files) {
    $idx++
    $dest = Join-Path $StageRoot $f.path
    $destParent = Split-Path $dest -Parent
    if (-not (Test-Path $destParent)) { New-Item -ItemType Directory -Path $destParent -Force | Out-Null }
    if (-not (Get-RepoFile -Ref $FileRef -RelPath $f.path -OutFile $dest -ExpectSha256 $f.sha256 -ExpectSize $f.size)) {
        Write-Bad "第 $idx/$($manifest.files.Count) 个文件下载或校验失败：$($f.path)"
        Finish 1
    }
    Write-Host ("  ({0}/{1}) {2}" -f $idx, $manifest.files.Count, $f.path) -ForegroundColor DarkGray
}
Write-Ok '全部文件 SHA-256 与大小校验通过'

# ---------- 5. 确定安装落点（真实目录，绝不 junction） ----------
Write-Step '确定 node_modules 落点'
$nmLocal  = Join-Path $profileDir 'node_modules'
$nmRoot   = Join-Path $ProfilesRoot 'node_modules'
if (Test-Path $nmLocal)                 { $nmTarget = $nmLocal }
elseif (Test-Path $nmRoot)              { $nmTarget = $nmRoot }   # pnpm workspace hoisted 布局
else                                    { $nmTarget = $nmLocal; New-Item -ItemType Directory -Path $nmLocal -Force | Out-Null }
$installDir = Join-Path $nmTarget $PluginId
Write-Ok "安装目录 = $installDir"

if (Test-ReparsePoint $nmTarget) {
    Write-Bad "node_modules 本身是链接（$nmTarget），违反桌面端闸门要求，中止。"
    Finish 1
}

# cordis.patch.yml 若已注册本插件会报 duplicate loader entry，预先拦截
$patchFile = Join-Path $profileDir 'cordis.patch.yml'
if (Test-Path $patchFile) {
    $patchText = [IO.File]::ReadAllText($patchFile)
    if ($patchText -match 'our-free-model') {
        Write-Bad "cordis.patch.yml 中已存在 our-free-model 条目。"
        Write-Host '  按规范 bundle 引用的包其 patch 层自动生效，两处同时注册将报错'
        Write-Host '  duplicate loader entry id: our-free-model。请先移除该条目再安装。'
        Finish 1
    }
}

# ---------- 6. 写入 profile 的 package.json（dependencies + dsh.profile.bundles） ----------
$pkgPath = Join-Path $profileDir 'package.json'
Write-Step "编辑 profile package.json（$pkgPath）"
try { $pkgText = [IO.File]::ReadAllText($pkgPath); $pkg = $pkgText | ConvertFrom-Json } catch {
    Write-Bad "package.json 解析失败：$_"; Finish 1
}

if ($Uninstall) {
    Write-Step '卸载模式'
    $changed = $false
    if ($pkg.PSObject.Properties['dependencies'] -and $pkg.dependencies.PSObject.Properties[$PluginId]) {
        $pkg.dependencies.PSObject.Properties.Remove($PluginId); $changed = $true
        Write-Ok '已移除 dependencies 条目'
    }
    if ($pkg.PSObject.Properties['dsh'] -and $pkg.dsh.PSObject.Properties['profile'] -and $pkg.dsh.profile.PSObject.Properties['bundles']) {
        $keep = @($pkg.dsh.profile.bundles | Where-Object { $_ -ne $PluginId })
        if ($keep.Count -ne @($pkg.dsh.profile.bundles).Count) {
            if ($keep.Count -eq 0) { $pkg.dsh.profile.PSObject.Properties.Remove('bundles') }
            else { $pkg.dsh.profile.bundles = $keep }
            $changed = $true
            Write-Ok '已移除 dsh.profile.bundles 条目'
        }
    }
    if ($changed) {
        Copy-Item -LiteralPath $pkgPath -Destination "$pkgPath.bak-ofm" -Force
        $json = $pkg | ConvertTo-Json -Depth 16
        [IO.File]::WriteAllText($pkgPath, $json, (New-Object Text.UTF8Encoding($false)))
    }
    if (Test-Path -LiteralPath $installDir) {
        Remove-Item -LiteralPath $installDir -Recurse -Force
        Write-Ok "已删除插件目录 $installDir"
    }
    Write-Host ''
    Write-Host '卸载完成。插件数据目录（可选删除）：' -ForegroundColor Yellow
    Write-Host "  $(Join-Path $home_ 'our-free-model')"
    Finish 0
}

if (-not $pkg.PSObject.Properties['dependencies']) {
    $pkg | Add-Member -MemberType NoteProperty -Name 'dependencies' -Value ([pscustomobject]@{}) -Force
}
$pkg.dependencies | Add-Member -MemberType NoteProperty -Name $PluginId -Value $ver -Force

if (-not $pkg.PSObject.Properties['dsh']) {
    $pkg | Add-Member -MemberType NoteProperty -Name 'dsh' -Value ([pscustomobject]@{}) -Force
}
if (-not $pkg.dsh.PSObject.Properties['profile']) {
    $pkg.dsh | Add-Member -MemberType NoteProperty -Name 'profile' -Value ([pscustomobject]@{}) -Force
}
if (-not $pkg.dsh.profile.PSObject.Properties['bundles']) {
    $pkg.dsh.profile | Add-Member -MemberType NoteProperty -Name 'bundles' -Value @() -Force
}
$bundles = @($pkg.dsh.profile.bundles)
$already = $bundles -contains $PluginId
if ($already -and $bundles.Count -gt 1) {
    $pkg.dsh.profile.bundles = @($bundles | Where-Object { $_ -ne $PluginId }) + $PluginId   # 规范要求追加到末尾
} elseif (-not $already) {
    $pkg.dsh.profile.bundles = $bundles + $PluginId
}
Write-Ok "dependencies.dsh-our-free-model = $ver"
Write-Ok 'dsh.profile.bundles 末尾已包含 dsh-our-free-model'

# ---------- 7. 备份旧版本并落盘 ----------
if (Test-Path -LiteralPath $installDir) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $bak = "${installDir}.bak-$stamp"
    Move-Item -LiteralPath $installDir -Destination $bak -Force
    $oldVer = ''
    try { $oldVer = ([IO.File]::ReadAllText((Join-Path $bak 'package.json')) | ConvertFrom-Json).version } catch {}
    Write-Warn2 "检测到旧版本（$oldVer），已备份至 $(Split-Path $bak -Leaf)"
}
New-Item -ItemType Directory -Path $installDir -Force | Out-Null
Copy-Item -Path (Join-Path $StageRoot '*') -Destination $installDir -Recurse -Force -Exclude 'feed-manifest.json'
if (Test-ReparsePoint $installDir) {
    Write-Bad '安装目录意外成为链接，中止（请手动检查）。'; Finish 1
}
Write-Ok '插件文件已复制（真实目录，非链接）'

Copy-Item -LiteralPath $pkgPath -Destination "$pkgPath.bak-ofm" -Force
$json = $pkg | ConvertTo-Json -Depth 16
[IO.File]::WriteAllText($pkgPath, $json, (New-Object Text.UTF8Encoding($false)))
Write-Ok 'package.json 已更新（原文件备份为 package.json.bak-ofm）'

# ---------- 8. 自检 ----------
Write-Step '自检'
$checkOk = $true

$installedPkg = [IO.File]::ReadAllText((Join-Path $installDir 'package.json')) | ConvertFrom-Json
if ($installedPkg.version -ne $ver) { Write-Bad "安装目录内版本 $($installedPkg.version) 与 $ver 不一致"; $checkOk = $false }
else { Write-Ok "版本一致：$ver" }

$after = [IO.File]::ReadAllText($pkgPath) | ConvertFrom-Json
if ($after.dependencies.$PluginId -ne $ver) { Write-Bad 'dependencies 条目校验失败'; $checkOk = $false }
$bc = @($after.dsh.profile.bundles | Where-Object { $_ -eq $PluginId }).Count
if ($bc -ne 1) { Write-Bad "bundles 中出现 $bc 次 dsh-our-free-model（应为 1 次）"; $checkOk = $false }
else { Write-Ok 'bundles 条目唯一且位于末尾' }

foreach ($must in @('index.js', 'client.js', 'adapter', 'src', 'locale', 'icon.svg', 'cordis.patch.yml', 'package.json')) {
    if (-not (Test-Path -LiteralPath (Join-Path $installDir $must))) {
        Write-Bad "缺少发布文件：$must（adapter/ 不可遗漏：index.js 首行即 import 该目录）"; $checkOk = $false
    }
}
if ($checkOk) { Write-Ok '关键文件齐全（index.js / client.js / adapter/ / src/ / locale/ …）' }

# 桌面 profile：扫描闸门敏感的链接（dsh 自身在 .dsh-module-fallback 下生成的除外）
if ($ProfileName -in @('web-desktop', 'desktop')) {
    Write-Step '桌面闸门预扫描（符号链接 / junction）'
    $foreign = @()
    foreach ($scanRoot in @($profileDir, $nmRoot)) {
        if (-not (Test-Path $scanRoot)) { continue }
        try {
            $foreign += Get-ChildItem -LiteralPath $scanRoot -Recurse -Depth 4 -Force -Attributes ReparsePoint -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -notmatch '\.dsh-module-fallback' }
        } catch {}
    }
    $foreign = $foreign | Sort-Object FullName -Unique
    if ($foreign.Count -gt 0) {
        Write-Warn2 "profile 树内发现 $($foreign.Count) 个非 .dsh-module-fallback 链接，可能导致启动报错："
        Write-Host '  PROFILE_UPGRADE_REQUIRED: offline dependency migration is not yet available'
        $foreign | Select-Object -First 10 | ForEach-Object { Write-Host "   - $($_.FullName)" -ForegroundColor DarkYellow }
        Write-Host '  若启动受阻：关闭桌面端，删除该 profile 的 node_modules 与 pnpm-lock.yaml 后重试。'
    } else {
        Write-Ok '未发现闸门敏感链接'
    }
}

# ---------- 9. 完成 ----------
Write-Host ''
Write-Host '=================================================' -ForegroundColor Green
if ($checkOk) { Write-Host ' 安装完成 ✔' -ForegroundColor Green }
else { Write-Host ' 安装完成（存在告警，请阅读上文）' -ForegroundColor Yellow }
Write-Host '=================================================' -ForegroundColor Green
Write-Host "  插件目录 : $installDir"
Write-Host "  profile  : $ProfileName（$pkgPath）"
Write-Host "  数据目录 : $(Join-Path $home_ 'our-free-model')"
Write-Host ''
Write-Host '  下一步：重启 dsh / 桌面端一次。' -ForegroundColor White
Write-Host '  验证（可选）：dsh --profile <名称> --dump-config | grep our-free-model'
Write-Host '  应只出现一个 id: our-free-model。模型选择器中会出现 Our Free Model 分组。'
Write-Host '  若启动报 ERR_PNPM_VIRTUAL_STORE_DIR_MAX_LENGTH_DIFF：关闭应用，删除该'
Write-Host '  profile 的 node_modules 与 pnpm-lock.yaml 使其重建，再重跑本脚本。'
Write-Host '  卸载：重新运行本脚本并加 -Uninstall 参数。'
Finish $(if ($checkOk) { 0 } else { 2 })
