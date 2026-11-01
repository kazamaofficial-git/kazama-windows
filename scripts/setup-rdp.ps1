# ============================================================
# Kazama Windows - enable RDP + create the login user (GitHub Actions mode)
# Developer  : @kazamaofficial-git
# ============================================================
# Reads : RDP_PASSWORD (secret) / RDP_PASSWORD_VAR (variable), KZ_USERNAME
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Kazama.psm1') -Force

$username = if ($env:KZ_USERNAME) { $env:KZ_USERNAME } else { 'kazama' }
$password = Get-KzSecret 'RDP_PASSWORD'

if ([string]::IsNullOrEmpty($password)) {
    Stop-Kz "RDP_PASSWORD is missing. Add it in Settings > Secrets and variables > Actions." `
            "RDP_PASSWORD belum diisi. Tambahkan di Settings > Secrets and variables > Actions."
}
if ($username -notmatch '^[A-Za-z][A-Za-z0-9_-]{0,19}$') {
    Stop-Kz "Invalid username '$username' (letters, digits, _ or -, max 20, must start with a letter)." `
            "Username '$username' tidak valid (huruf, angka, _ atau -, maks 20, harus diawali huruf)."
}
$classes = @('[a-z]', '[A-Z]', '[0-9]', '[^a-zA-Z0-9]') | Where-Object { $password -cmatch $_ }
if ($password.Length -lt 8 -or @($classes).Count -lt 3 -or $password -like "*$username*") {
    Stop-Kz "RDP_PASSWORD must be 8+ chars, mix 3 of: lower, UPPER, digits, symbols, and not contain the username." `
            "RDP_PASSWORD minimal 8 karakter, campuran 3 dari: huruf kecil, BESAR, angka, simbol, dan tidak boleh memuat username."
}
Write-Host "::add-mask::$password"

# ---- user -------------------------------------------------------------------
$secure = ConvertTo-SecureString $password -AsPlainText -Force
if (Get-LocalUser -Name $username -ErrorAction SilentlyContinue) {
    Set-LocalUser -Name $username -Password $secure
    Write-KzInfo "User '$username' already exists - password updated" "User '$username' sudah ada - password diperbarui"
} else {
    New-LocalUser -Name $username -Password $secure -FullName 'Kazama RDP' -PasswordNeverExpires -AccountNeverExpires | Out-Null
    Write-KzInfo "User '$username' created" "User '$username' berhasil dibuat"
}
foreach ($group in 'Administrators', 'Remote Desktop Users') {
    Add-LocalGroupMember -Group $group -Member $username -ErrorAction SilentlyContinue
}

# ---- RDP --------------------------------------------------------------------
$ts = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
Set-ItemProperty -Path $ts -Name 'fDenyTSConnections' -Value 0
Set-ItemProperty -Path "$ts\WinStations\RDP-Tcp" -Name 'UserAuthentication' -Value 1   # keep NLA enabled

if (-not (Get-NetFirewallRule -DisplayName 'Kazama RDP' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName 'Kazama RDP' -Direction Inbound -Protocol TCP -LocalPort 3389 -Action Allow | Out-Null
}
Set-Service -Name TermService -StartupType Automatic
Restart-Service -Name TermService -Force

powercfg /change monitor-timeout-ac 0 | Out-Null
powercfg /change standby-timeout-ac 0 | Out-Null

$ok = $false
foreach ($i in 1..15) {
    if ((Test-NetConnection -ComputerName 127.0.0.1 -Port 3389 -WarningAction SilentlyContinue).TcpTestSucceeded) { $ok = $true; break }
    Start-Sleep -Seconds 2
}
if (-not $ok) { Stop-Kz "RDP service is not listening on port 3389." "Layanan RDP tidak mendengarkan di port 3389." }
Write-KzInfo "RDP is ready on port 3389 (NLA enabled)" "RDP siap di port 3389 (NLA aktif)"
