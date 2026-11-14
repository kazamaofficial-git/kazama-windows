# ============================================================
# Kazama Windows - RDP connection self-test (GitHub Actions / native mode)
# Developer  : @kazamaofficial-git
# ============================================================
# Checks everything the server side controls and prints a table in the log and the job
# summary, so a failed connection can be traced to ONE line. Never fails the job.
# Reads: KZ_USERNAME, KZ_HOST (Tailscale IP, optional), KZ_LANG
[CmdletBinding()]
param()
$ErrorActionPreference = 'SilentlyContinue'
Import-Module (Join-Path $PSScriptRoot 'Kazama.psm1') -Force

$user = if ($env:KZ_USERNAME) { $env:KZ_USERNAME } else { 'kazama' }
$tsExe = 'C:\Program Files\Tailscale\tailscale.exe'
$rows = @()
function Add-Check([string]$Name, [string]$State, [string]$Detail) { $script:rows += [pscustomobject]@{ Check = $Name; State = $State; Detail = $Detail } }

# 1) listener
$listen = Get-NetTCPConnection -LocalPort 3389 -State Listen
Add-Check 'RDP listener on 3389' $(if ($listen) { 'OK' } else { 'FAIL' }) $(if ($listen) { ($listen | ForEach-Object { $_.LocalAddress } | Sort-Object -Unique) -join ', ' } else { 'nothing is listening - Remote Desktop Services is not serving RDP' })

# 2) service + registry
$svc = Get-Service -Name TermService
Add-Check 'Remote Desktop Services' $(if ($svc.Status -eq 'Running') { 'OK' } else { 'FAIL' }) "$($svc.Status)"
$ts = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
$deny = (Get-ItemProperty $ts).fDenyTSConnections
Add-Check 'RDP allowed (fDenyTSConnections)' $(if ($deny -eq 0) { 'OK' } else { 'FAIL' }) "value = $deny (0 = allowed)"
$nla = (Get-ItemProperty "$ts\WinStations\RDP-Tcp").UserAuthentication
Add-Check 'Network Level Authentication' 'INFO' $(if ($nla -eq 1) { 'enabled (client must support NLA; use COMPUTERNAME\user if credentials are rejected)' } else { 'disabled' })

# 3) firewall
$fw = Get-NetFirewallRule -DisplayName 'Kazama RDP'
Add-Check 'Firewall rule "Kazama RDP"' $(if ($fw -and $fw.Enabled -eq 'True') { 'OK' } else { 'WARN' }) $(if ($fw) { "enabled=$($fw.Enabled) profile=$($fw.Profile) action=$($fw.Action)" } else { 'rule missing (built-in Remote Desktop rules may still allow RDP)' })
$profiles = (Get-NetFirewallProfile | ForEach-Object { "$($_.Name)=$($_.Enabled)" }) -join ', '
Add-Check 'Windows Firewall profiles' 'INFO' $profiles

# 4) account
$netUser = (& net.exe user $user 2>&1 | Out-String)
if ($LASTEXITCODE -eq 0) {
    $active = $netUser -match 'Account active\s+Yes'
    $groups = ([regex]::Match($netUser, '(?s)Local Group Memberships(.*?)Global Group')).Groups[1].Value -replace '\*', '' -replace '\s+', ' '
    Add-Check "User '$user' exists and is active" $(if ($active) { 'OK' } else { 'FAIL' }) "active=$active"
    Add-Check "User '$user' may use RDP" $(if ($groups -match 'Administrators|Remote Desktop Users') { 'OK' } else { 'FAIL' }) $groups.Trim()
    $expired = $netUser -match 'Password expires\s+(?!Never)'
    Add-Check 'Password does not expire / need change' $(if (-not ($netUser -match 'Password last set\s+Never') -and -not $expired) { 'OK' } else { 'WARN' }) (($netUser -split "`r?`n" | Where-Object { $_ -match 'Password (last set|expires)' }) -join '; ')
} else {
    Add-Check "User '$user' exists" 'FAIL' 'net user could not find the account'
}

# 5) Tailscale
$tsIp = $env:KZ_HOST
if (Test-Path $tsExe) {
    $state = ((& $tsExe status --json 2>$null | ConvertFrom-Json).BackendState)
    $ip4 = (& $tsExe ip -4 2>$null | Select-Object -First 1)
    Add-Check 'Tailscale' $(if ($state -eq 'Running' -and $ip4) { 'OK' } else { 'FAIL' }) "state=$state ip=$ip4"
    if (-not $tsIp) { $tsIp = $ip4 }
    $category = (Get-NetConnectionProfile | Where-Object { $_.InterfaceAlias -like '*Tailscale*' }).NetworkCategory
    if ($category) { Add-Check 'Tailscale network category' 'INFO' "$category" }
}

# 6) reachability on the Tailscale address
if ($tsIp) {
    $reach = (Test-NetConnection -ComputerName $tsIp -Port 3389 -WarningAction SilentlyContinue).TcpTestSucceeded
    Add-Check "TCP $tsIp`:3389 from this machine" $(if ($reach) { 'OK' } else { 'FAIL' }) $(if ($reach) { 'connects' } else { 'refused / blocked - check firewall rules and the RDP listener' })
}

# 7) sessions
$sessions = (& qwinsta 2>&1 | Out-String).Trim()
Add-Check 'Sessions right now' 'INFO' (($sessions -split "`r?`n" | Select-Object -Skip 1 | ForEach-Object { $_.Trim() -replace '\s+', ' ' }) -join ' | ')

# ---- report ------------------------------------------------------------------
$failed = @($rows | Where-Object { $_.State -eq 'FAIL' })
Write-Host ''
foreach ($r in $rows) { Write-Host ('  [{0,-4}] {1} - {2}' -f $r.State, $r.Check, $r.Detail) }
Write-Host ''
if ($failed.Count -gt 0) {
    Write-Host ('::warning::[kazama] ' + (T "RDP self-test: $($failed.Count) check(s) FAILED - see the job summary." "Self-test RDP: $($failed.Count) pemeriksaan GAGAL - lihat job summary."))
} else {
    Write-KzInfo 'RDP self-test: server side looks fine.' 'Self-test RDP: sisi server terlihat baik.'
}

$table = ($rows | ForEach-Object { '| {0} | {1} | {2} |' -f $_.State, $_.Check, (($_.Detail -replace '\|', '/') -replace '\s+', ' ') }) -join "`n"
$computer = $env:COMPUTERNAME
Add-KzSummary @"

### 🔎 RDP self-test

| Result | Check | Detail |
|---|---|---|
$table

**If Windows App says the credentials are wrong**, sign in as ``$computer\$user`` (or ``.\$user``) instead of just ``$user``.
**If it cannot connect at all**, make sure Tailscale is running on your device and signed in to the same tailnet as ``$tsIp``.
"@
exit 0
