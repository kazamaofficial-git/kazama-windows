# ============================================================
# Kazama Performance Tuning — makes Windows light enough for emulation / small VMs
# Developer  : @kazamaofficial-git
# Repository : https://github.com/kazamaofficial-git/kazama-windows
# ============================================================
# On Railway there is no KVM, so Windows runs on software emulation (very slow). Most of the
# CPU is wasted on background work; this script switches that work off.
#
#   -Level light   power plan "High performance", Server Manager off at logon, telemetry /
#                  indexing / SysMain / error reporting services off, no maintenance tasks,
#                  minimal visual effects for new users, NTFS last-access updates off
#   -Level max     light + Windows Defender real-time protection off and Windows Update off
#                  (less secure — use only on a disposable desktop)
#
# Needs Administrator rights. Log: C:\Kazama\tune.log
[CmdletBinding()]
param(
    [ValidateSet('off', 'light', 'max')][string]$Level = 'light',
    [ValidateSet('en', 'id', '')][string]$Language = '',
    [switch]$Quiet
)
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

if ($Level -eq 'off') { return }

$lang = if ($Language) { $Language } elseif ($env:KZ_LANG -in 'en', 'id') { $env:KZ_LANG } else { 'en' }
function T([string]$En, [string]$Id) { if ($lang -eq 'id') { $Id } else { $En } }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Host (T 'Run as Administrator.' 'Jalankan sebagai Administrator.'); exit 1 }

New-Item -ItemType Directory -Force -Path 'C:\Kazama' | Out-Null
$log = 'C:\Kazama\tune.log'
$script:Applied = 0

function Step([string]$En, [string]$Id, [scriptblock]$Action) {
    $text = T $En $Id
    try {
        & $Action *> $null
        $script:Applied++
        $line = "  + $text"
    } catch {
        $line = "  ! $text ($($_.Exception.Message))"
    }
    "$(Get-Date -Format s)  $line" | Add-Content -Path $log
    if (-not $Quiet) { Write-Host $line }
}

function Disable-ServiceSafe([string]$Name) {
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($svc) {
        Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
        Set-Service -Name $Name -StartupType Disabled -ErrorAction SilentlyContinue
    }
}

function Set-RegValue([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord') {
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

if (-not $Quiet) { Write-Host ''; Write-Host ('  KAZAMA Tune - {0}' -f $Level) -ForegroundColor Cyan }

# ---- light ------------------------------------------------------------------
Step 'Power plan: High performance, no sleep' 'Power plan: High performance, tanpa sleep' {
    powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
    powercfg /change monitor-timeout-ac 0
    powercfg /change standby-timeout-ac 0
    powercfg /change disk-timeout-ac 0
}

Step 'Server Manager does not open at logon' 'Server Manager tidak dibuka saat logon' {
    Set-RegValue 'HKLM:\SOFTWARE\Microsoft\ServerManager' 'DoNotOpenServerManagerAtLogon' 1
    Get-ScheduledTask -TaskName 'ServerManager' -ErrorAction SilentlyContinue | Disable-ScheduledTask | Out-Null
}

Step 'Background services off (telemetry, indexing, SysMain, error reporting)' 'Service latar belakang dimatikan (telemetri, indexing, SysMain, error reporting)' {
    foreach ($name in 'DiagTrack', 'dmwappushservice', 'SysMain', 'WSearch', 'WerSvc') { Disable-ServiceSafe $name }
}

Step 'Scheduled maintenance and telemetry tasks off' 'Task maintenance dan telemetri dimatikan' {
    $tasks = @(
        '\Microsoft\Windows\TaskScheduler\Regular Maintenance',
        '\Microsoft\Windows\TaskScheduler\Idle Maintenance',
        '\Microsoft\Windows\Defrag\ScheduledDefrag',
        '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
        '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
        '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
        '\Microsoft\Windows\Windows Error Reporting\QueueReporting',
        '\Microsoft\Windows\Diagnosis\Scheduled'
    )
    foreach ($t in $tasks) { & schtasks.exe /Change /TN $t /Disable 2>$null | Out-Null }
}

Step 'Minimal visual effects for new users' 'Efek visual minimal untuk user baru' {
    $hive = 'C:\Users\Default\NTUSER.DAT'
    & reg.exe load 'HKU\KZDEF' $hive | Out-Null
    try {
        Set-RegValue 'Registry::HKEY_USERS\KZDEF\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 2
        Set-RegValue 'Registry::HKEY_USERS\KZDEF\Control Panel\Desktop' 'MenuShowDelay' '0' 'String'
        Set-RegValue 'Registry::HKEY_USERS\KZDEF\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '0' 'String'
        Set-RegValue 'Registry::HKEY_USERS\KZDEF\Control Panel\Desktop' 'UserPreferencesMask' ([byte[]](0x90, 0x12, 0x03, 0x80, 0x10, 0x00, 0x00, 0x00)) 'Binary'
    } finally {
        [gc]::Collect(); [gc]::WaitForPendingFinalizers()
        & reg.exe unload 'HKU\KZDEF' | Out-Null
    }
}

Step 'NTFS: no last-access timestamps' 'NTFS: tanpa timestamp akses terakhir' {
    & fsutil.exe behavior set disablelastaccess 1
}

# ---- max --------------------------------------------------------------------
if ($Level -eq 'max') {
    Step 'Windows Defender real-time protection off' 'Windows Defender real-time dimatikan' {
        Set-MpPreference -DisableRealtimeMonitoring $true -DisableBehaviorMonitoring $true -DisableIOAVProtection $true -MAPSReporting 0 -SubmitSamplesConsent 2
        Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender' 'DisableAntiSpyware' 1
    }
    Step 'Windows Update off' 'Windows Update dimatikan' {
        Set-RegValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'NoAutoUpdate' 1
        foreach ($name in 'wuauserv', 'UsoSvc', 'WaaSMedicSvc') { Disable-ServiceSafe $name }
    }
}

if (-not $Quiet) {
    Write-Host ''
    Write-Host ('  {0}: {1}' -f (T 'Applied' 'Diterapkan'), $script:Applied) -ForegroundColor Green
    Write-Host (T '  Restart Windows once so every change takes effect.' '  Restart Windows sekali agar semua perubahan berlaku.')
}
