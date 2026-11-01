# ============================================================
# Kazama Windows — in-Windows setup (booster, wallpaper, shortcuts)
# Developer  : @kazamaofficial-git
# Repository : https://github.com/kazamaofficial-git/kazama-windows
# ============================================================
# Used by BOTH modes:
#   Railway  : C:\OEM\install.bat runs it once at the end of the Windows install
#   Actions  : the workflow runs it right after enabling RDP
#
# Settings come from parameters, else from kazama.conf next to this script, else defaults.
#   LANG=en|id   BOOSTER=off|safe|deep   SCHEDULE=off|daily|weekly   WALLPAPER=true|false
[CmdletBinding()]
param(
    [string]$Language,
    [string]$Booster,
    [string]$Schedule,
    [string]$Wallpaper,
    [switch]$RunNow
)
$ErrorActionPreference = 'Continue'

# ---- settings ---------------------------------------------------------------
$conf = @{}
$confFile = Join-Path $PSScriptRoot 'kazama.conf'
if (Test-Path $confFile) {
    foreach ($line in Get-Content $confFile) {
        if ($line -match '^\s*([A-Z_]+)\s*=\s*(.*?)\s*$') { $conf[$Matches[1]] = $Matches[2] }
    }
}
function Resolve-Setting([string]$Param, [string]$Key, [string]$Default, [string[]]$Allowed) {
    $value = if ($Param) { $Param } elseif ($conf.ContainsKey($Key)) { $conf[$Key] } else { $Default }
    $value = $value.ToLowerInvariant()
    if ($Allowed -notcontains $value) { return $Default }
    return $value
}
$lang = Resolve-Setting $Language 'LANG' 'en' @('en', 'id')
$boost = Resolve-Setting $Booster 'BOOSTER' 'safe' @('off', 'safe', 'deep')
$sched = Resolve-Setting $Schedule 'SCHEDULE' 'weekly' @('off', 'daily', 'weekly')
$wall = Resolve-Setting $Wallpaper 'WALLPAPER' 'true' @('true', 'false')

function T([string]$En, [string]$Id) { if ($lang -eq 'id') { $Id } else { $En } }
function Write-Kz([string]$En, [string]$Id) { Write-Host ('[kazama] ' + (T $En $Id)) }

# ---- install files to C:\Kazama ---------------------------------------------
$dir = 'C:\Kazama'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
foreach ($file in 'kazama-booster.ps1', 'kazama-wallpaper.ps1') {
    Copy-Item -Path (Join-Path $PSScriptRoot $file) -Destination $dir -Force
}
$image = @((Join-Path $PSScriptRoot 'wallpaper.png'), (Join-Path $PSScriptRoot '..\assets\wallpaper.png')) |
    Where-Object { Test-Path $_ } | Select-Object -First 1
if ($image) { Copy-Item -Path $image -Destination (Join-Path $dir 'wallpaper.png') -Force }

@("LANG=$lang", "BOOSTER=$boost", "SCHEDULE=$sched", "WALLPAPER=$wall") | Set-Content -Path (Join-Path $dir 'kazama.conf') -Encoding ascii
Write-Kz "Kazama files installed in $dir" "File Kazama dipasang di $dir"

$ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$flags = '-NoProfile -ExecutionPolicy Bypass'

# ---- wallpaper (once per user, at logon) ------------------------------------
if ($wall -eq 'true' -and (Test-Path (Join-Path $dir 'wallpaper.png'))) {
    # Make sure the RDP session actually draws the desktop background.
    Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'fDisableWallpaper' -Value 0 -ErrorAction SilentlyContinue
    $tsPolicy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
    if (Test-Path $tsPolicy) { Set-ItemProperty $tsPolicy -Name 'fNoRemoteDesktopWallpaper' -Value 0 -ErrorAction SilentlyContinue }

    $action = New-ScheduledTaskAction -Execute $ps -Argument "$flags -WindowStyle Hidden -File `"$dir\kazama-wallpaper.ps1`""
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $principal = New-ScheduledTaskPrincipal -GroupId 'BUILTIN\Users' -RunLevel Limited
    Register-ScheduledTask -TaskName 'Kazama Wallpaper' -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
    Write-Kz 'Wallpaper task registered' 'Task wallpaper terdaftar'
}

# ---- storage booster: desktop shortcut + schedule ---------------------------
if ($boost -ne 'off') {
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut('C:\Users\Public\Desktop\Kazama Storage Booster.lnk')
    $lnk.TargetPath = $ps
    $lnk.Arguments = "$flags -File `"$dir\kazama-booster.ps1`" -Mode $boost -Language $lang"
    $lnk.WorkingDirectory = $dir
    $lnk.IconLocation = "$env:SystemRoot\System32\cleanmgr.exe,0"
    $lnk.Description = 'Kazama Storage Booster'
    $lnk.Save()
    Write-Kz 'Desktop shortcut "Kazama Storage Booster" created' 'Shortcut desktop "Kazama Storage Booster" dibuat'

    if ($sched -ne 'off') {
        $action = New-ScheduledTaskAction -Execute $ps -Argument "$flags -File `"$dir\kazama-booster.ps1`" -Mode $boost -Language $lang -Quiet -NoPause"
        $trigger = if ($sched -eq 'daily') { New-ScheduledTaskTrigger -Daily -At '03:00' } else { New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At '03:00' }
        $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        Register-ScheduledTask -TaskName 'Kazama Storage Booster' -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
        Write-Kz "Booster scheduled ($sched, 03:00)" "Booster dijadwalkan ($sched, 03:00)"
    }
}

# ---- run once now -----------------------------------------------------------
if ($RunNow -and $boost -ne 'off') {
    & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dir 'kazama-booster.ps1') -Mode $boost -Language $lang -Quiet -NoPause
}
