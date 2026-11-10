# ============================================================
# Kazama Windows — install on a Windows machine you control (NO virtual machine, NO emulation)
# Developer  : @kazamaofficial-git
# Repository : https://github.com/kazamaofficial-git/kazama-windows
# ============================================================
# Turns a real Windows Server / Windows 10-11 Pro host into a ready RDP desktop:
#   RDP + login user + (optional) Tailscale + Storage Booster + tuning + Kazama wallpaper.
# Because Windows runs natively, you get full speed and the host's real GPU.
#
# Run from an elevated PowerShell, inside a checkout/ZIP of this repository:
#   powershell -ExecutionPolicy Bypass -File windows\install-windows.ps1 -Username kazama -TailscaleAuthKey tskey-auth-...
# The password is asked interactively (never put it on the command line).
#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]$Username = 'kazama',
    [SecureString]$Password,
    [string]$TailscaleAuthKey,
    [string]$TailscaleHostname = 'kazama-windows',
    [ValidateSet('off', 'safe', 'deep', 'max')][string]$Booster = 'safe',
    [ValidateSet('off', 'light', 'max')][string]$Tune = 'off',
    [ValidateSet('en', 'id')][string]$Language = 'en',
    [string]$Keep = 'chrome',
    [switch]$SkipWallpaper
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$scripts = Join-Path $repo 'scripts'
function T([string]$En, [string]$Id) { if ($Language -eq 'id') { $Id } else { $En } }
function Say([string]$En, [string]$Id) { Write-Host ('[kazama] ' + (T $En $Id)) }

if (-not (Test-Path (Join-Path $scripts 'setup-rdp.ps1'))) {
    throw (T 'Run this script from inside the kazama-windows repository (scripts\setup-rdp.ps1 not found).' 'Jalankan skrip ini dari dalam repository kazama-windows (scripts\setup-rdp.ps1 tidak ditemukan).')
}

$caption = (Get-CimInstance Win32_OperatingSystem).Caption
if ($caption -match 'Home') {
    throw (T "$caption cannot host Remote Desktop connections. Use Windows Pro/Enterprise or Windows Server." "$caption tidak bisa menjadi host Remote Desktop. Gunakan Windows Pro/Enterprise atau Windows Server.")
}
Say "Host: $caption" "Host: $caption"

# ---- password (interactive, never echoed) ------------------------------------
if (-not $Password) {
    $first = Read-Host (T 'RDP password' 'Password RDP') -AsSecureString
    $second = Read-Host (T 'Repeat password' 'Ulangi password') -AsSecureString
    $a = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($first))
    $b = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($second))
    if ($a -ne $b) { throw (T 'Passwords do not match.' 'Password tidak sama.') }
    $Password = $first
}
$plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password))

# ---- 1) RDP + user (same logic as the GitHub Actions mode) -----------------------
$env:KZ_LANG = $Language
$env:KZ_USERNAME = $Username
$env:RDP_PASSWORD = $plain
& (Join-Path $scripts 'setup-rdp.ps1')
if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw (T 'RDP setup failed.' 'Setup RDP gagal.') }
Remove-Item Env:\RDP_PASSWORD -ErrorAction SilentlyContinue

# ---- 2) Tailscale (optional) ----------------------------------------------------
$address = $null
if ($TailscaleAuthKey) {
    $ts = 'C:\Program Files\Tailscale\tailscale.exe'
    if (-not (Test-Path $ts)) {
        Say 'Installing Tailscale ...' 'Memasang Tailscale ...'
        $msi = Join-Path $env:TEMP 'tailscale-setup.msi'
        Invoke-WebRequest -Uri 'https://pkgs.tailscale.com/stable/tailscale-setup-latest-amd64.msi' -OutFile $msi -UseBasicParsing
        Start-Process msiexec.exe -ArgumentList '/i', "`"$msi`"", '/qn', '/norestart' -Wait
    }
    if (-not (Test-Path $ts)) { throw (T 'Tailscale could not be installed.' 'Tailscale gagal dipasang.') }
    Start-Service -Name Tailscale -ErrorAction SilentlyContinue
    & $ts up "--authkey=$TailscaleAuthKey" "--hostname=$TailscaleHostname" --unattended --reset
    if ($LASTEXITCODE -ne 0) { throw (T 'tailscale up failed - check the auth key.' 'tailscale up gagal - periksa auth key.') }
    $address = (& $ts ip -4 2>$null | Select-Object -First 1)
}

# ---- 3) Kazama desktop: booster, tuning, wallpaper -------------------------------
$wallpaper = if ($SkipWallpaper) { 'false' } else { 'true' }
& (Join-Path $PSScriptRoot 'kazama-setup.ps1') -Language $Language -Booster $Booster -Keep $Keep -Tune $Tune -Wallpaper $wallpaper -Schedule weekly -RunNow

# ---- done -----------------------------------------------------------------------
if (-not $address) {
    $address = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' } | Select-Object -First 1).IPAddress
}
Write-Host ''
Write-Host '==============================================' -ForegroundColor Cyan
Write-Host (' ' + (T 'Kazama Windows RDP is ready' 'Kazama Windows RDP siap')) -ForegroundColor Cyan
Write-Host "   PC name  : $address"
Write-Host "   Username : $Username"
Write-Host ('   Password : ' + (T 'the one you just entered' 'yang baru Anda masukkan'))
Write-Host '==============================================' -ForegroundColor Cyan
Write-Host (T 'Connect with Windows App (PC name above). Over the internet, prefer Tailscale instead of opening port 3389.' 'Hubungkan dengan Windows App (PC name di atas). Lewat internet, utamakan Tailscale daripada membuka port 3389.')
