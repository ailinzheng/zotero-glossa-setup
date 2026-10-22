# Windows PowerShell 5.1 or newer. No administrator rights or extra runtimes.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:AddonID = 'glossa-zotero@yiiwang118'
$script:ExpectedHash = '0a71b777731e856ac3ad8d1fceaf598fce6cc15a8ca6a459902bc9b74462a8c9'

function Read-IniSections([string]$Path) {
    $sections = [ordered]@{}
    $current = ''
    foreach ($line in [IO.File]::ReadAllLines($Path, [Text.Encoding]::UTF8)) {
        $s = $line.Trim().TrimStart([char]0xFEFF)
        if (!$s -or $s.StartsWith(';') -or $s.StartsWith('#')) { continue }
        if ($s -match '^\[([^\]]+)\]$') {
            $current = $matches[1]
            $sections[$current] = @{}
        } elseif ($current -and $s -match '^([^=]+)=(.*)$') {
            $sections[$current][$matches[1].Trim()] = $matches[2].Trim()
        }
    }
    return ,$sections
}

function Get-ZoteroProfiles([string]$IniPath) {
    $sections = Read-IniSections $IniPath
    $base = Split-Path -Parent $IniPath
    foreach ($section in $sections.Keys) {
        if ($section -notmatch '^Profile\d+$') { continue }
        $p = $sections[$section]
        if (!$p.ContainsKey('Path')) { continue }
        $path = $p['Path']
        if (!$p.ContainsKey('IsRelative') -or $p['IsRelative'] -ne '0') {
            $path = Join-Path $base $path
        }
        $path = [IO.Path]::GetFullPath($path)
        if (!(Test-Path -LiteralPath $path -PathType Container)) { continue }
        $label = $section
        if ($p.ContainsKey('Name')) { $label = $p['Name'] }
        [pscustomobject]@{Name=$label; Path=$path}
    }
}

function Test-CompatibleVersion([string]$Version) {
    if ($Version -notmatch '^10\.(\d+)(?:\.(\d+))?$') { return $false }
    $minor = [int]$matches[1]
    $patch = 0
    if ($matches[2]) { $patch = [int]$matches[2] }
    return ($minor -gt 0 -or $patch -ge 6)
}

function Read-AddonVersion([string]$Xpi) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($Xpi)
    try {
        $entry = $zip.GetEntry('manifest.json')
        if (!$entry) { throw '已有插件缺少 manifest.json，请在 Zotero 插件管理器中处理。' }
        $reader = New-Object IO.StreamReader($entry.Open())
        try { $manifest = $reader.ReadToEnd() | ConvertFrom-Json }
        finally { $reader.Dispose() }
        if ($manifest.applications.zotero.id -ne $script:AddonID) { throw '已有插件的 ID 不符合预期，已停止。' }
        return [string]$manifest.version
    } finally { $zip.Dispose() }
}

function Install-GlossaToProfile([string]$Profile, [string]$Source) {
    if ((Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash.ToLowerInvariant() -ne $script:ExpectedHash) {
        throw '插件 SHA-256 校验失败。请重新下载本压缩包，或从作者发布页下载原版 XPI。'
    }
    $extensions = Join-Path $Profile 'extensions'
    $target = Join-Path $extensions ($script:AddonID + '.xpi')
    foreach ($special in @((Join-Path $extensions $script:AddonID),
                           (Join-Path $extensions ('staged/' + $script:AddonID)),
                           (Join-Path $extensions ('staged/' + $script:AddonID + '.xpi')))) {
        if (Test-Path -LiteralPath $special) {
            throw '发现解包版插件或尚未完成的安装/移除。请先重启 Zotero，再从“工具 → 插件”安装包内 XPI。'
        }
    }
    if (Test-Path -LiteralPath $target) {
        $version = Read-AddonVersion $target
        if ($version -eq '0.1.0') {
            throw '作者要求先移除 Glossa 0.1.0 并重启 Zotero，再安装 0.2.0。请先完成这一步。'
        }
        if ($version -notmatch '^\d+\.\d+\.\d+$' -or [version]$version -gt [version]'0.2.0') {
            throw "已装版本为 $version；为避免降级，已停止。"
        }
        if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -eq $script:ExpectedHash) {
            return [pscustomobject]@{Changed=$false; Backup=''}
        }
    }
    $stamp = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
    $backup = Join-Path $Profile ('glossa-setup-backups/' + $stamp)
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    $prefs = Join-Path $Profile 'prefs.js'
    $hadTarget = Test-Path -LiteralPath $target
    $hadPrefs = Test-Path -LiteralPath $prefs
    if ($hadTarget) { Copy-Item -LiteralPath $target -Destination (Join-Path $backup 'previous.xpi') }
    if ($hadPrefs) { Copy-Item -LiteralPath $prefs -Destination (Join-Path $backup 'prefs.js') }
    New-Item -ItemType Directory -Path $extensions -Force | Out-Null
    $temporary = Join-Path $extensions ('.glossa-setup-' + $stamp + '.tmp')
    $prefsTemporary = Join-Path $Profile ('.glossa-prefs-' + $stamp + '.tmp')
    $targetTouched = $false
    $prefsTouched = $false
    try {
        Copy-Item -LiteralPath $Source -Destination $temporary
        $targetTouched = $true
        Move-Item -LiteralPath $temporary -Destination $target -Force
        # Clear only two startup cache markers to request an extension rescan.
        # Keep all security preferences, disabled states, API keys and other settings.
        if ($hadPrefs) {
            $old = [IO.File]::ReadAllText($prefs, [Text.Encoding]::UTF8)
            $new = [regex]::Replace($old, '(?m)^[\t ]*user_pref\("extensions\.lastApp(?:BuildId|Version)"[^\r\n]*(?:\r?\n|$)', '')
            if ($new -cne $old) {
                [IO.File]::WriteAllText($prefsTemporary, $new, (New-Object Text.UTF8Encoding($false)))
                $prefsTouched = $true
                [IO.File]::Replace($prefsTemporary, $prefs, [NullString]::Value)
            }
        }
    } catch {
        if ($targetTouched) {
            if ($hadTarget) { Copy-Item -LiteralPath (Join-Path $backup 'previous.xpi') -Destination $target -Force }
            elseif (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Force }
        }
        if ($prefsTouched) { Copy-Item -LiteralPath (Join-Path $backup 'prefs.js') -Destination $prefs -Force }
        throw
    } finally {
        foreach ($temp in @($temporary,$prefsTemporary)) {
            if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }
        }
    }
    return [pscustomobject]@{Changed=$true; Backup=$backup}
}

function Find-ZoteroExecutable {
    $candidates = New-Object 'Collections.Generic.List[string]'
    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA)) {
        if ($root) {
            $candidates.Add((Join-Path $root 'Zotero/zotero.exe'))
            $candidates.Add((Join-Path $root 'Programs/Zotero/zotero.exe'))
        }
    }
    foreach ($key in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\zotero.exe',
                       'HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths\zotero.exe')) {
        if (Test-Path $key) {
            $value = (Get-Item $key).GetValue('')
            if ($value) { $candidates.Add(([string]$value).Trim('"')) }
        }
    }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object Windows.Forms.OpenFileDialog
    $dialog.Title = '请选择 Zotero 安装目录中的 zotero.exe'
    $dialog.Filter = 'Zotero (zotero.exe)|zotero.exe'
    if ($dialog.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { throw '未选择 Zotero，已取消。' }
    return $dialog.FileName
}

function Invoke-GlossaSetup {
    Write-Host 'Zotero + Claude / Glossa 0.2.0 安装助手' -ForegroundColor Cyan
    $exe = Find-ZoteroExecutable
    $ini = Join-Path (Split-Path -Parent $exe) 'application.ini'
    if (!(Test-Path -LiteralPath $ini)) { throw '找不到 Zotero 的 application.ini，无法核对版本。请使用包内的手动安装方式。' }
    $config = Read-IniSections $ini
    $version = [string]$config['App']['Version']
    Write-Host "Zotero 版本：$version"
    if (!(Test-CompatibleVersion $version)) {
        throw '此插件仅支持 Zotero 10.0.6 及以后的正式版 10.x。请先核对或更新 Zotero。'
    }
    if (Get-Process -Name zotero -ErrorAction SilentlyContinue) {
        [void](Read-Host '请先保存工作并完全退出 Zotero，然后按回车继续（助手不会强制关闭）')
    }
    if (Get-Process -Name zotero -ErrorAction SilentlyContinue) { throw 'Zotero 仍在运行，请完全退出后重试。' }
    $iniCandidates = @((Join-Path $env:APPDATA 'Zotero/Zotero/profiles.ini'),
                       (Join-Path $env:APPDATA 'Zotero/profiles.ini'))
    $profiles = @()
    foreach ($candidate in $iniCandidates) {
        if (Test-Path -LiteralPath $candidate) { $profiles += @(Get-ZoteroProfiles $candidate) }
    }
    $profiles = @($profiles | Sort-Object Path -Unique)
    if (!$profiles.Count) { throw '未找到 Zotero 配置。请先正常启动 Zotero 一次并退出。便携版/自定义配置请使用手动安装。' }
    $profile = $profiles[0]
    if ($profiles.Count -gt 1) {
        for ($i=0; $i -lt $profiles.Count; $i++) { Write-Host ("[{0}] {1}  {2}" -f ($i+1),$profiles[$i].Name,$profiles[$i].Path) }
        $answer = Read-Host '找到多个配置，请输入要安装的编号'
        $selected = 0
        if (![int]::TryParse($answer, [ref]$selected) -or $selected -lt 1 -or $selected -gt $profiles.Count) { throw '未选择有效配置，已取消。' }
        $profile = $profiles[$selected-1]
    }
    if (Get-Process -Name zotero -ErrorAction SilentlyContinue) { throw '检测到 Zotero 已重新启动，请退出后重试。' }
    $source = Join-Path $PSScriptRoot 'payload/glossa-zotero-0.2.0.xpi'
    $result = Install-GlossaToProfile $profile.Path $source
    if ($result.Changed) {
        Write-Host '插件文件已部署。' -ForegroundColor Green
        Write-Host ('本次备份：' + $result.Backup)
    } else { Write-Host '原版 0.2.0 插件文件已存在，无需重复复制。' -ForegroundColor Green }
    Write-Host '请到 Zotero 的“工具 → 插件”确认 Glossa；如果显示“启用”，请点一次。'
    Write-Host '然后选中文献 → Glossa → 模型菜单 → 添加 API 服务 → Anthropic。'
    Write-Host '密钥只需在 Zotero 内填写；完整中文说明即将打开。'
    try { Start-Process -FilePath $exe -ArgumentList @('-profile', ('"' + $profile.Path + '"'), '-purgecaches') | Out-Null }
    catch { Write-Warning '插件文件已部署，但未能自动打开 Zotero。请手动启动。' }
    try { Start-Process -FilePath (Join-Path $PSScriptRoot 'README.html') | Out-Null }
    catch { Write-Host '请手动打开同目录的 README.html。' }
}

# Dot-sourcing exposes functions for isolated checks without running installation.
if ($MyInvocation.InvocationName -ne '.') {
    try { Invoke-GlossaSetup; exit 0 }
    catch {
        Write-Host ''
        Write-Host ('未完成：' + $_.Exception.Message) -ForegroundColor Red
        Write-Host '也可打开 Zotero → 工具 → 插件，将 payload 中的 .xpi 文件拖入窗口安装。'
        exit 1
    }
}
