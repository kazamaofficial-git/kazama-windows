# ============================================================
# Kazama Windows - keep the session alive (GitHub Actions mode)
# Developer  : @kazamaofficial-git
# ============================================================
# Reads : KZ_DURATION (minutes, 10-345), KZ_IDLE (minutes, 0 = never stop on idle)
# Ends when: the time limit is reached, nobody has been connected for KZ_IDLE minutes,
#            or the file C:\kazama\STOP exists. Cancelling the workflow run also works.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Kazama.psm1') -Force

function ConvertTo-Minutes([string]$Value, [int]$Default, [int]$Min, [int]$Max) {
    $n = 0
    if (-not [int]::TryParse($Value, [ref]$n)) { $n = $Default }
    [Math]::Min([Math]::Max($n, $Min), $Max)
}

$duration = ConvertTo-Minutes $env:KZ_DURATION 330 10 345
$idleMax = ConvertTo-Minutes $env:KZ_IDLE 30 0 345
$stopFile = 'C:\kazama\STOP'
New-Item -ItemType Directory -Force -Path (Split-Path $stopFile) | Out-Null
Remove-Item $stopFile -Force -ErrorAction SilentlyContinue

$start = Get-Date
$deadline = $start.AddMinutes($duration)
$lastActive = $start
$lastLog = $start.AddMinutes(-10)

Write-KzInfo "Session running for up to $duration min (idle stop: $idleMax min)" `
             "Sesi berjalan hingga $duration menit (stop saat idle: $idleMax menit)"

while ($true) {
    $now = Get-Date
    $active = @(quser 2>$null | Select-String '\sActive\s').Count
    if ($active -gt 0) { $lastActive = $now }

    if (Test-Path $stopFile) { Write-KzInfo "Stop file found - ending session" "File STOP ditemukan - mengakhiri sesi"; break }
    if ($now -ge $deadline) { Write-KzInfo "Time limit reached - ending session" "Batas waktu tercapai - mengakhiri sesi"; break }
    if ($idleMax -gt 0 -and ($now - $lastActive).TotalMinutes -ge $idleMax) {
        Write-KzInfo "No active RDP session for $idleMax min - ending session" "Tidak ada sesi RDP aktif selama $idleMax menit - mengakhiri sesi"
        break
    }
    if (($now - $lastLog).TotalMinutes -ge 5) {
        $left = [int]($deadline - $now).TotalMinutes
        Write-KzInfo "Alive - $left min left, active sessions: $active" "Aktif - sisa $left menit, sesi aktif: $active"
        $lastLog = $now
    }
    Start-Sleep -Seconds 20
}
