# ============================================================
# Kazama Windows - private access via Tailscale (GitHub Actions mode)
# Developer  : @kazamaofficial-git
# ============================================================
# Reads  : TAILSCALE_AUTHKEY (secret) / TAILSCALE_AUTHKEY_VAR (variable), KZ_TS_HOSTNAME
# Output : host, port  ($GITHUB_OUTPUT)
# Tip    : use an EPHEMERAL, reusable auth key so the node disappears when the run ends.
# You must have Tailscale running on the device you connect FROM.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Kazama.psm1') -Force

$key = Get-KzSecret 'TAILSCALE_AUTHKEY'
if ([string]::IsNullOrEmpty($key)) {
    Stop-Kz "TAILSCALE_AUTHKEY is missing (create one at https://login.tailscale.com/admin/settings/keys)." `
            "TAILSCALE_AUTHKEY belum diisi (buat di https://login.tailscale.com/admin/settings/keys)."
}
Write-Host "::add-mask::$key"

Write-KzInfo "Installing Tailscale ..." "Memasang Tailscale ..."
& (Get-KzChoco) install tailscale -y --no-progress --limit-output 2>&1 | Out-Null

$ts = 'C:\Program Files\Tailscale\tailscale.exe'
if (-not (Test-Path $ts)) { Stop-Kz "Tailscale could not be installed." "Tailscale gagal dipasang." }
Start-Service -Name Tailscale -ErrorAction SilentlyContinue

$name = if ($env:KZ_TS_HOSTNAME) { $env:KZ_TS_HOSTNAME } else { "kazama-win-$($env:GITHUB_RUN_ID)" }
& $ts up "--authkey=$key" "--hostname=$name" --unattended --reset 2>&1 | ForEach-Object { Write-Host "$_" }
if ($LASTEXITCODE -ne 0) { Stop-Kz "tailscale up failed - check the auth key." "tailscale up gagal - periksa auth key." }

$ip = $null
foreach ($i in 1..15) {
    $ip = (& $ts ip -4 2>$null | Select-Object -First 1)
    if ($ip) { break }
    Start-Sleep -Seconds 2
}
if (-not $ip) { Stop-Kz "Could not get a Tailscale IP." "Gagal mendapatkan IP Tailscale." }

# Windows firewall treats unknown networks as Public: mark the Tailscale network Private (best effort).
[void](Invoke-KzOptional 'Tailscale network category' {
    Get-NetConnectionProfile | Where-Object { $_.InterfaceAlias -like '*Tailscale*' } | Set-NetConnectionProfile -NetworkCategory Private -ErrorAction Stop
})

Set-KzOutput -Name 'host' -Value $ip
Set-KzOutput -Name 'name' -Value $name
Write-KzInfo "Tailscale ready: $ip ($name)" "Tailscale siap: $ip ($name)"
