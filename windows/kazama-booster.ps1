# ============================================================
# Kazama Storage Booster
# Developer  : @kazamaofficial-git
# Repository : https://github.com/kazamaofficial-git/kazama-windows
# ============================================================
# Frees disk space on C: by deleting files Windows can rebuild or never needs.
#
#   -Mode safe   caches, temp files, update leftovers, crash dumps, browser caches
#   -Mode deep   safe + component-store clean-up (DISM /StartComponentCleanup; add /ResetBase with
#                KZ_DISM_RESETBASE=true), hibernation file,
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
# Expected, harmless failures (file in use, path missing) must never turn the log red.
# Real problems are reported per step in the Diagnostics section instead.
$ErrorActionPreference = 'SilentlyContinue'
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

function Invoke-WithTimeout([string]$File, [string[]]$Arguments, [int]$Seconds = 600) {
    <# Runs a program hidden and NEVER waits longer than $Seconds (the process is killed). Returns its exit code, or -1 on timeout. #>
    $proc = Start-Process -FilePath $File -ArgumentList $Arguments -PassThru -WindowStyle Hidden
    if (-not $proc) { return -2 }
    if (-not $proc.WaitForExit($Seconds * 1000)) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        return -1
    }
    return $proc.ExitCode
}

function Remove-Tree([string]$Path, [int]$TimeoutSeconds = 900) {
    <# Deletes folders/files matching $Path (wildcards allowed).
       Folders are emptied by mirroring an EMPTY folder over them with robocopy: multi-threaded, long-path safe, and in
       backup mode (/B) so ACLs / TrustedInstaller ownership do not matter. This replaces the old takeown /R + icacls /T
       fallback, which could run for a very long time on huge trees such as Visual Studio. #>
    foreach ($item in @(Get-Item -Path $Path -Force -ErrorAction SilentlyContinue)) {
        $full = $item.FullName
        if (-not $item.PSIsContainer) { Remove-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue; continue }
        $empty = Join-Path $env:TEMP 'kazama-empty'
        New-Item -ItemType Directory -Force -Path $empty | Out-Null
        [void](Invoke-WithTimeout 'robocopy.exe' @("`"$empty`"", "`"$full`"", '/MIR', '/B', '/R:0', '/W:0', '/MT:64', '/NFL', '/NDL', '/NJH', '/NJS', '/NP') $TimeoutSeconds)
        [void](Invoke-WithTimeout 'cmd.exe' @('/d', '/c', "rd /s /q `"\\?\$full`"") 120)
    }
}

function Get-UserProfiles {
    Get-ChildItem -Path 'C:\Users' -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin 'Public', 'Default', 'Default User', 'All Users' }
}

$script:Results = @()
$script:Diag = @()
function Invoke-Step([string]$En, [string]$Id, [scriptblock]$Action) {
    $name = T $En $Id
    $before = Get-FreeBytes
    $clock = [Diagnostics.Stopwatch]::StartNew()
    if (-not $Quiet) { Write-Host ('  * {0} ...' -f $name) -NoNewline }
    $Error.Clear()
    try { & $Action *> $null } catch { $script:Diag += [pscustomobject]@{ Step = $name; Count = 1; First = $_.Exception.Message } }
    # Errors swallowed by -ErrorAction SilentlyContinue are still collected in $Error: keep the first one.
    if ($Error.Count -gt 0 -and -not ($script:Diag | Where-Object { $_.Step -eq $name })) {
        $script:Diag += [pscustomobject]@{ Step = $name; Count = $Error.Count; First = (@($Error)[0].Exception.Message -replace '\s+', ' ') }
    }
    $freed = [Math]::Max(0, (Get-FreeBytes) - $before)
    $seconds = [int]$clock.Elapsed.TotalSeconds
    if (-not $Quiet) { Write-Host (' +{0}  ({1}s)' -f (Format-Size $freed), $seconds) -ForegroundColor Green }
    $script:Results += [pscustomobject]@{ Step = $name; Freed = $freed; Seconds = $seconds }
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
    if (-not $proc.WaitForExit(300000)) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
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
            Invoke-WebRequest -Uri 'https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi' -OutFile $msi -UseBasicParsing -TimeoutSec 120
            [void](Invoke-WithTimeout 'msiexec.exe' @('/i', "`"$msi`"", '/qn', '/norestart') 300)
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
        [void](Invoke-WithTimeout $setup.FullName @('--uninstall', '--system-level', '--verbose-logging', '--force-uninstall') 300)
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
    Invoke-Step 'Windows component store cleanup (DISM)' 'Pembersihan component store Windows (DISM)' {
        # /ResetBase frees more but can take 10-20 minutes: opt in with KZ_DISM_RESETBASE=true.
        $dismArgs = @('/Online', '/Cleanup-Image', '/StartComponentCleanup')
        if ($env:KZ_DISM_RESETBASE -eq 'true') { $dismArgs += '/ResetBase' }
        [void](Invoke-WithTimeout 'dism.exe' $dismArgs 900)
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
    $catalog = @{ Apps = @() }
    try {
        if (Test-Path $catalogFile) { $catalog = Import-PowerShellDataFile -Path $catalogFile -ErrorAction Stop }
        else { Write-Host ('  ! ' + (T 'Catalog file not found - nothing to remove' 'File katalog tidak ditemukan - tidak ada yang dihapus')) -ForegroundColor Yellow }
    } catch {
        Write-Host ('  ! ' + (T 'Catalog could not be read: ' 'Katalog tidak bisa dibaca: ') + $_.Exception.Message) -ForegroundColor Yellow
    }

    foreach ($app in $catalog.Apps) {
        if ($script:KeepList -contains $app.Id.ToLowerInvariant()) { continue }
        if ($app.OnlyOn -and ($app.OnlyOn -notcontains $script:Profile.Id)) { continue }
        if (-not (Test-CatalogEntryPresent $app)) { continue }
        $entry = $app
        Invoke-Step ("Remove $($entry.Name)") ("Hapus $($entry.Name)") { Invoke-CatalogRemoval $entry }
    }
}

# TRIM: lets the virtual disk reclaim the space we just freed.
if ($env:GITHUB_ACTIONS -ne 'true') {
    Invoke-Step 'Disk TRIM' 'TRIM disk' {
        Optimize-Volume -DriveLetter C -ReTrim -ErrorAction SilentlyContinue
    }
}

# ---- report -----------------------------------------------------------------
$endFree = Get-FreeBytes
$gained = [Math]::Max(0, $endFree - $startFree)
$line = '{0}: {1}  ->  {2}  (+{3})' -f (T 'Free space' 'Ruang kosong'), (Format-Size $startFree), (Format-Size $endFree), (Format-Size $gained)

"$(Get-Date -Format s)  [$Mode]  $line" | Add-Content -Path $log -ErrorAction SilentlyContinue
foreach ($d in $script:Diag) {
    "$(Get-Date -Format s)  [diag] $($d.Step): $($d.Count) message(s) - $($d.First)" | Add-Content -Path $log -ErrorAction SilentlyContinue
}

if ($env:GITHUB_STEP_SUMMARY) {
    $rows = ($script:Results | Where-Object { $_.Freed -gt 0 } | ForEach-Object { '| {0} | {1} | {2}s |' -f $_.Step, (Format-Size $_.Freed), $_.Seconds }) -join "`n"
    $diagRows = ($script:Diag | ForEach-Object { '| {0} | {1} | {2} |' -f $_.Step, $_.Count, (($_.First -replace '\|', '/') -replace '\s+', ' ') }) -join "`n"
    Add-Content -Path $env:GITHUB_STEP_SUMMARY -Encoding utf8 -Value @"

### Kazama Storage Booster ($Mode · $($script:Profile.Id))

**$line**

| Step | Freed | Time |
|---|---|---|
$rows

"@
    if ($diagRows) {
        Add-Content -Path $env:GITHUB_STEP_SUMMARY -Encoding utf8 -Value @"

#### Diagnostics - non-fatal messages per step

Usually harmless (a file in use, a path that does not exist). Look closer only if a step you expected to free space shows nothing.

| Step | Messages | First message |
|---|---|---|
$diagRows

"@
    }
}

if ($Quiet) {
    Write-Host "[kazama] $line"
    if ($script:Diag.Count -gt 0) {
        Write-Host ("::notice::[kazama] " + (T "$($script:Diag.Count) booster step(s) reported non-fatal messages - details in the job summary and C:\Kazama\booster.log" "$($script:Diag.Count) langkah booster melaporkan pesan non-fatal - detail ada di job summary dan C:\Kazama\booster.log"))
    }
} else {
    Write-Host ''
    Write-Host "  $line" -ForegroundColor Cyan
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host (T 'Press Enter to close' 'Tekan Enter untuk menutup')) }
}
