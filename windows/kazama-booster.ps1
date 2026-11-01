# ============================================================
# Kazama Storage Booster
# Developer  : @kazamaofficial-git
# Repository : https://github.com/kazamaofficial-git/kazama-windows
# ============================================================
# Frees disk space on C: by deleting files Windows can rebuild or never needs.
#
#   -Mode safe   caches, temp files, update leftovers, crash dumps, browser caches
#   -Mode deep   safe + component-store clean-up (DISM /ResetBase), hibernation file,
#                shadow copies, event logs, Windows.old and (on GitHub runners)
#                big pre-installed SDKs you do not need in a remote desktop
#
# Shows "free space before -> after" at the end. Needs Administrator rights and
# re-launches itself elevated when started from a normal prompt.
[CmdletBinding()]
param(
    [ValidateSet('safe', 'deep')][string]$Mode = 'safe',
    [ValidateSet('en', 'id', '')][string]$Language = '',
    [switch]$Quiet,
    [switch]$NoPause
)
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

# ---- language ---------------------------------------------------------------
function Get-KzLanguage {
    if ($Language) { return $Language }
    if ($env:KZ_LANG -in 'en', 'id') { return $env:KZ_LANG }
    $conf = 'C:\Kazama\kazama.conf'
    if (Test-Path $conf) {
        $line = Get-Content $conf | Where-Object { $_ -match '^LANG=(en|id)\s*$' } | Select-Object -First 1
        if ($line) { return ($line -split '=')[1].Trim() }
    }
    return 'en'
}
$script:Lang = Get-KzLanguage
function T([string]$En, [string]$Id) { if ($script:Lang -eq 'id') { $Id } else { $En } }

# ---- elevate ----------------------------------------------------------------
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $relaunch = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Mode', $Mode, '-Language', $script:Lang)
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
    if (-not (Test-Path -LiteralPath $Path)) { return }
    & takeown.exe /F $Path /R /D Y 2>&1 | Out-Null
    & icacls.exe $Path /grant 'Administrators:F' /T /C /Q 2>&1 | Out-Null
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
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

# ---- start ------------------------------------------------------------------
$startFree = Get-FreeBytes
$logDir = 'C:\Kazama'
New-Item -ItemType Directory -Force -Path $logDir -ErrorAction SilentlyContinue | Out-Null
$log = Join-Path $logDir 'booster.log'

if (-not $Quiet) {
    Write-Host ''
    Write-Host '  KAZAMA Storage Booster' -ForegroundColor Cyan
    Write-Host ('  {0}: {1}   {2}: {3}' -f (T 'Mode' 'Mode'), $Mode, (T 'Free now' 'Kosong sekarang'), (Format-Size $startFree))
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
if ($Mode -eq 'deep') {
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

    # Pre-installed toolchains on GitHub-hosted runners that a remote desktop never needs.
    if ($env:GITHUB_ACTIONS -eq 'true') {
        Invoke-Step 'Pre-installed SDKs on the runner' 'SDK bawaan di runner' {
            $bulky = @(
                'C:\Android',
                'C:\Program Files (x86)\Android',
                'C:\ghcup',
                'C:\Miniconda',
                'C:\mysql',
                'C:\Program Files\PostgreSQL',
                'C:\Program Files\MongoDB'
            )
            foreach ($d in $bulky) { Remove-Tree $d }
        }
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

### Kazama Storage Booster ($Mode)

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
