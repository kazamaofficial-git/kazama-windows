# ============================================================
# Kazama Storage Booster
# Developer  : @kazamaofficial-git
# Repository : https://github.com/kazamaofficial-git/kazama-windows
# ============================================================
# Frees disk space on C: by deleting files Windows can rebuild or never needs.
#
#   -Mode safe   caches, temp files, update leftovers, crash dumps, browser caches
#   -Mode deep   safe + component-store clean-up (DISM /ResetBase), hibernation file,
#                shadow copies, event logs, Windows.old, installer cache
#   -Mode max    deep + REMOVES apps/SDKs listed in kazama-catalog.psd1 (Edge, Firefox,
#                Unity, R, Haskell, Android, Julia, Miniconda, Visual Studio, databases ...).
#                Google Chrome is always kept (and installed first if Edge is to be removed).
#                Protect more entries with -Keep, e.g. -Keep chrome,visualstudio
#
# Windows 2022 / 2025 are detected from the build number; version-specific folders are
# matched with wildcards, and each catalog entry only runs when it is actually installed.
#
# Shows "free space before -> after" at the end. Needs Administrator rights and
# re-launches itself elevated when started from a normal prompt.
[CmdletBinding()]
param(
    [ValidateSet('safe', 'deep', 'max')][string]$Mode = 'safe',
    [ValidateSet('en', 'id', '')][string]$Language = '',
    [string]$Keep = '',
    [switch]$Quiet,
    [switch]$NoPause
)
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

# ---- settings ---------------------------------------------------------------
function Get-KzConf([string]$Key) {
    $conf = 'C:\Kazama\kazama.conf'
    if (-not (Test-Path $conf)) { return $null }
    $line = Get-Content $conf | Where-Object { $_ -match "^$Key=" } | Select-Object -First 1
    if ($line) { return ($line -split '=', 2)[1].Trim() }
    return $null
}
function Get-KzLanguage {
    if ($Language) { return $Language }
    if ($env:KZ_LANG -in 'en', 'id') { return $env:KZ_LANG }
    $fromConf = Get-KzConf 'LANG'
    if ($fromConf -in 'en', 'id') { return $fromConf }
    return 'en'
}
$script:Lang = Get-KzLanguage
$keepRaw = if ($Keep) { $Keep } elseif ($env:KZ_KEEP) { $env:KZ_KEEP } elseif (Get-KzConf 'KEEP') { Get-KzConf 'KEEP' } else { 'chrome' }
$script:KeepList = @(($keepRaw -split '[,\s]+') | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() })
function T([string]$En, [string]$Id) { if ($script:Lang -eq 'id') { $Id } else { $En } }

# ---- elevate ----------------------------------------------------------------
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $relaunch = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Mode', $Mode, '-Language', $script:Lang, '-Keep', ($script:KeepList -join ','))
    if ($Quiet) { $relaunch += '-Quiet' }
    if ($NoPause) { $relaunch += '-NoPause' }
    Start-Process -FilePath 'powershell.exe' -ArgumentList $relaunch -Verb RunAs
    exit 0
}

# ---- helpers ----------------------------------------------------------------
function Get-FreeBytes { [int64](Get-PSDrive -Name C).Free }

function Format-Size([int64]$Bytes) {
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N0} MB' -f ($Bytes / 1MB)) }
    return ('{0:N0} KB' -f ($Bytes / 1KB))
}

function Remove-Contents([string]$Path) {
    foreach ($item in @(Get-Item -Path $Path -Force -ErrorAction SilentlyContinue)) {
        if ($item.PSIsContainer) {
            Get-ChildItem -LiteralPath $item.FullName -Force -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            Remove-Item -LiteralPath $item.FullName -Force -ErrorAction SilentlyContinue
        }
    }
}

function Remove-Tree([string]$Path) {
    <# Deletes folders/files matching $Path (wildcards allowed). `rd` with the \\?\ prefix is far faster than
       Remove-Item on huge trees and copes with very long paths; ownership is taken only if needed. #>
    foreach ($item in @(Get-Item -Path $Path -Force -ErrorAction SilentlyContinue)) {
        $full = $item.FullName
        if (-not $item.PSIsContainer) { Remove-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue; continue }
        & cmd.exe /d /c "rd /s /q `"\\?\$full`"" 2>&1 | Out-Null
        if (Test-Path -LiteralPath $full) {
            & takeown.exe /F $full /R /D Y 2>&1 | Out-Null
            & icacls.exe $full /grant 'Administrators:F' /T /C /Q 2>&1 | Out-Null
            & cmd.exe /d /c "rd /s /q `"\\?\$full`"" 2>&1 | Out-Null
        }
    }
}

function Get-UserProfiles {
    Get-ChildItem -Path 'C:\Users' -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin 'Public', 'Default', 'Default User', 'All Users' }
}

$script:Results = @()
function Invoke-Step([string]$En, [string]$Id, [scriptblock]$Action) {
    $before = Get-FreeBytes
    if (-not $Quiet) { Write-Host ('  * {0} ...' -f (T $En $Id)) -NoNewline }
    try { & $Action *> $null } catch { }
    $freed = [Math]::Max(0, (Get-FreeBytes) - $before)
    if (-not $Quiet) { Write-Host (' +{0}' -f (Format-Size $freed)) -ForegroundColor Green }
    $script:Results += [pscustomobject]@{ Step = (T $En $Id); Freed = $freed }
}

function Stop-ServiceSafe([string]$Name) {
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq 'Running') {
        Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
        return $true
    }
    return $false
}


# ---- Windows profile --------------------------------------------------------
function Get-WindowsProfile {
    $build = [Environment]::OSVersion.Version.Build
    $id = if ($build -ge 26100) { 'win2025' } elseif ($build -ge 20348) { 'win2022' } else { 'other' }
    [pscustomobject]@{ Id = $id; Build = $build }
}
$script:Profile = Get-WindowsProfile

# ---- app removal helpers (Max mode) -----------------------------------------
function Get-UninstallEntries {
    $keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    Get-ItemProperty -Path $keys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName }
}

function Invoke-UninstallEntry($Entry) {
    $cmd = if ($Entry.QuietUninstallString) { $Entry.QuietUninstallString } else { $Entry.UninstallString }
    if (-not $cmd) { return }

    if ($cmd -match 'msiexec') {
        $guid = [regex]::Match($cmd, '\{[0-9A-Fa-f\-]+\}').Value
        if (-not $guid) { return }
        $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList '/x', $guid, '/qn', '/norestart' -PassThru -WindowStyle Hidden
    } else {
        $silent = ''
        if (-not $Entry.QuietUninstallString) {
            $silent = if ($cmd -match 'unins\d*\.exe') { ' /VERYSILENT /SUPPRESSMSGBOXES /NORESTART' } else { ' /S' }
        }
        $proc = Start-Process -FilePath 'cmd.exe' -ArgumentList '/d', '/s', '/c', "`"$cmd$silent`"" -PassThru -WindowStyle Hidden
    }
    # An uninstaller that waits for user input must never block the booster.
    if (-not $proc.WaitForExit(600000)) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
}

function Test-ChromeInstalled {
    (Test-Path 'C:\Program Files\Google\Chrome\Application\chrome.exe') -or
    (Test-Path 'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe')
}

function Install-Chrome {
    if (Test-ChromeInstalled) { return $true }
    $choco = Get-Command choco -ErrorAction SilentlyContinue
    if ($choco) { & $choco.Source install googlechrome -y --no-progress --limit-output | Out-Null }
    if (-not (Test-ChromeInstalled)) {
        $msi = Join-Path $env:TEMP 'kazama-chrome.msi'
        try {
            Invoke-WebRequest -Uri 'https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi' -OutFile $msi -UseBasicParsing
            Start-Process -FilePath 'msiexec.exe' -ArgumentList '/i', "`"$msi`"", '/qn', '/norestart' -Wait -WindowStyle Hidden
        } catch { }
    }
    return (Test-ChromeInstalled)
}

function Remove-Edge {
    # Never leave the machine without a browser: Chrome first, Edge second.
    if (-not (Install-Chrome)) {
        Write-Host ('  ! ' + (T 'Chrome could not be installed - Edge is kept' 'Chrome gagal dipasang - Edge dipertahankan')) -ForegroundColor Yellow
        return $false
    }
    Get-Process -Name 'msedge*' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    $setup = Get-ChildItem 'C:\Program Files (x86)\Microsoft\Edge\Application\*\Installer\setup.exe' -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1
    if ($setup) {
        Start-Process -FilePath $setup.FullName -Wait -WindowStyle Hidden `
            -ArgumentList '--uninstall', '--system-level', '--verbose-logging', '--force-uninstall'
    }
    return $true
}

function Test-CatalogEntryPresent($App) {
    foreach ($f in @($App.Folders)) { if ($f -and (Test-Path -Path $f)) { return $true } }
    foreach ($pattern in @($App.Display)) {
        if ($pattern -and (Get-UninstallEntries | Where-Object { $_.DisplayName -like $pattern })) { return $true }
    }
    return $false
}

function Invoke-CatalogRemoval($App) {
    foreach ($pattern in @($App.Services)) {
        if (-not $pattern) { continue }
        Get-Service -Name $pattern -ErrorAction SilentlyContinue | ForEach-Object {
            Stop-Service -Name $_.Name -Force -ErrorAction SilentlyContinue
            Set-Service -Name $_.Name -StartupType Disabled -ErrorAction SilentlyContinue
        }
    }
    $edgeOk = $true
    if ($App.Special -eq 'edge') { $edgeOk = Remove-Edge }
    elseif ($App.Display) {
        foreach ($pattern in @($App.Display)) {
            Get-UninstallEntries | Where-Object { $_.DisplayName -like $pattern } | ForEach-Object { Invoke-UninstallEntry $_ }
        }
    }
    if ($edgeOk) { foreach ($f in @($App.Folders)) { if ($f) { Remove-Tree $f } } }
}

# ---- start ------------------------------------------------------------------
$startFree = Get-FreeBytes
$logDir = 'C:\Kazama'
New-Item -ItemType Directory -Force -Path $logDir -ErrorAction SilentlyContinue | Out-Null
$log = Join-Path $logDir 'booster.log'

if (-not $Quiet) {
    Write-Host ''
    Write-Host '  KAZAMA Storage Booster' -ForegroundColor Cyan
    Write-Host ('  {0}: {1}   {2}: {3}' -f (T 'Mode' 'Mode'), $Mode, (T 'Free now' 'Kosong sekarang'), (Format-Size $startFree))
    Write-Host ('  Windows: {0} (build {1})   Keep: {2}' -f $script:Profile.Id, $script:Profile.Build, ($script:KeepList -join ', '))
    Write-Host ''
}

# ---- safe steps -------------------------------------------------------------
Invoke-Step 'Temporary files' 'File sementara' {
    Remove-Contents 'C:\Windows\Temp\*'
    Remove-Contents 'C:\Windows\Minidump\*'
    Remove-Item 'C:\Windows\MEMORY.DMP' -Force -ErrorAction SilentlyContinue
    foreach ($p in Get-UserProfiles) {
        Remove-Contents (Join-Path $p.FullName 'AppData\Local\Temp\*')
        Remove-Contents (Join-Path $p.FullName 'AppData\Local\CrashDumps\*')
    }
}

Invoke-Step 'Windows Update download cache' 'Cache unduhan Windows Update' {
    $wu = Stop-ServiceSafe 'wuauserv'
    $bits = Stop-ServiceSafe 'bits'
    Remove-Contents 'C:\Windows\SoftwareDistribution\Download\*'
    if ($bits) { Start-Service -Name 'bits' -ErrorAction SilentlyContinue }
    if ($wu) { Start-Service -Name 'wuauserv' -ErrorAction SilentlyContinue }
}

Invoke-Step 'Delivery Optimization cache' 'Cache Delivery Optimization' {
    if (Get-Command Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue) {
        Delete-DeliveryOptimizationCache -Force -ErrorAction SilentlyContinue
    }
    Remove-Contents 'C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache\*'
}

Invoke-Step 'Error reports and logs' 'Laporan error dan log' {
    Remove-Contents 'C:\ProgramData\Microsoft\Windows\WER\ReportArchive\*'
    Remove-Contents 'C:\ProgramData\Microsoft\Windows\WER\ReportQueue\*'
    Remove-Contents 'C:\ProgramData\Microsoft\Windows\WER\Temp\*'
    Remove-Item 'C:\Windows\Logs\CBS\*.log', 'C:\Windows\Logs\CBS\*.cab' -Force -ErrorAction SilentlyContinue
}

Invoke-Step 'Browser caches (Edge / Chrome)' 'Cache browser (Edge / Chrome)' {
    $cacheDirs = 'Cache', 'Code Cache', 'GPUCache'
    $browsers = 'AppData\Local\Microsoft\Edge\User Data\Default', 'AppData\Local\Google\Chrome\User Data\Default'
    foreach ($p in Get-UserProfiles) {
        foreach ($b in $browsers) {
            foreach ($c in $cacheDirs) { Remove-Contents (Join-Path $p.FullName "$b\$c\*") }
        }
    }
}

Invoke-Step 'Package manager caches' 'Cache package manager' {
    Remove-Contents 'C:\ProgramData\chocolatey\lib-bad\*'
    foreach ($p in Get-UserProfiles) {
        Remove-Contents (Join-Path $p.FullName 'AppData\Local\npm-cache\*')
        Remove-Contents (Join-Path $p.FullName 'AppData\Local\pip\Cache\*')
    }
}

Invoke-Step 'Recycle Bin' 'Recycle Bin' {
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
}

# ---- deep steps -------------------------------------------------------------
if ($Mode -in 'deep', 'max') {
    Invoke-Step 'Windows component store (DISM /ResetBase)' 'Component store Windows (DISM /ResetBase)' {
        Start-Process -FilePath 'dism.exe' -Wait -WindowStyle Hidden `
            -ArgumentList '/Online', '/Cleanup-Image', '/StartComponentCleanup', '/ResetBase'
    }
    Invoke-Step 'Hibernation file' 'File hibernasi' {
        & powercfg.exe -h off
    }
    Invoke-Step 'Shadow copies / restore points' 'Shadow copy / restore point' {
        & vssadmin.exe delete shadows /all /quiet
    }
    Invoke-Step 'Event logs' 'Event log' {
        foreach ($name in (& wevtutil.exe el)) { & wevtutil.exe cl $name 2>$null }
    }
    Invoke-Step 'Old Windows installs' 'Sisa instalasi Windows lama' {
        foreach ($d in 'C:\Windows.old', 'C:\$WINDOWS.~BT', 'C:\$WINDOWS.~WS') { Remove-Tree $d }
        Remove-Tree 'C:\Windows\Installer\$PatchCache$'
    }
    Invoke-Step 'Installer package cache' 'Cache paket installer' {
        Remove-Contents 'C:\ProgramData\Package Cache\*'
        Remove-Contents 'C:\Windows\ServiceProfiles\*\AppData\Local\Temp\*'
        Remove-Contents 'C:\Windows\System32\config\systemprofile\AppData\Local\Temp\*'
    }
}

# ---- max: remove apps and SDKs from the catalog ------------------------------
if ($Mode -eq 'max') {
    $catalogFile = Join-Path $PSScriptRoot 'kazama-catalog.psd1'
    if (-not (Test-Path $catalogFile)) { $catalogFile = 'C:\Kazama\kazama-catalog.psd1' }
    $catalog = if (Test-Path $catalogFile) { Import-PowerShellDataFile -Path $catalogFile } else { @{ Apps = @() } }

    foreach ($app in $catalog.Apps) {
        if ($script:KeepList -contains $app.Id.ToLowerInvariant()) { continue }
        if ($app.OnlyOn -and ($app.OnlyOn -notcontains $script:Profile.Id)) { continue }
        if (-not (Test-CatalogEntryPresent $app)) { continue }
        $entry = $app
        Invoke-Step ("Remove $($entry.Name)") ("Hapus $($entry.Name)") { Invoke-CatalogRemoval $entry }
    }
}

# TRIM: lets the virtual disk reclaim the space we just freed.
Invoke-Step 'Disk TRIM' 'TRIM disk' {
    Optimize-Volume -DriveLetter C -ReTrim -ErrorAction SilentlyContinue
}

# ---- report -----------------------------------------------------------------
$endFree = Get-FreeBytes
$gained = [Math]::Max(0, $endFree - $startFree)
$line = '{0}: {1}  ->  {2}  (+{3})' -f (T 'Free space' 'Ruang kosong'), (Format-Size $startFree), (Format-Size $endFree), (Format-Size $gained)

"$(Get-Date -Format s)  [$Mode]  $line" | Add-Content -Path $log -ErrorAction SilentlyContinue

if ($env:GITHUB_STEP_SUMMARY) {
    $rows = ($script:Results | Where-Object { $_.Freed -gt 0 } | ForEach-Object { '| {0} | {1} |' -f $_.Step, (Format-Size $_.Freed) }) -join "`n"
    Add-Content -Path $env:GITHUB_STEP_SUMMARY -Encoding utf8 -Value @"

### Kazama Storage Booster ($Mode · $($script:Profile.Id))

**$line**

| Step | Freed |
|---|---|
$rows

"@
}

if ($Quiet) {
    Write-Host "[kazama] $line"
} else {
    Write-Host ''
    Write-Host "  $line" -ForegroundColor Cyan
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host (T 'Press Enter to close' 'Tekan Enter untuk menutup')) }
}
