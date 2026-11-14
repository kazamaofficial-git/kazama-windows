# ============================================================
# Kazama Windows - enable RDP + create the login user (GitHub Actions / native mode)
# Developer  : @kazamaofficial-git
# ============================================================
# Reads : RDP_PASSWORD (secret) / RDP_PASSWORD_VAR (variable), KZ_USERNAME, KZ_RDP_NLA ('false' disables NLA - troubleshooting only)
#
# Critical steps (user, RDP on, service) stop the job with a clear ::error::.
# Optional steps (firewall rule, power settings) only produce a yellow ::warning::
# that names the step - the log never shows anonymous red lines.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Kazama.psm1') -Force

$username = if ($env:KZ_USERNAME) { $env:KZ_USERNAME } else { 'kazama' }
$password = Get-KzSecret 'RDP_PASSWORD'

# ---- validation -------------------------------------------------------------
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

# ---- 1) user (critical) -------------------------------------------------------
Start-KzGroup 'Create the login user' 'Buat user login'
try {
    $state = Set-KzLocalUser -Name $username -Password $password
    if ($state -eq 'created') { Write-KzInfo "User '$username' created" "User '$username' berhasil dibuat" }
    else { Write-KzInfo "User '$username' already exists - password updated" "User '$username' sudah ada - password diperbarui" }
} catch {
    Stop-Kz "Could not create/update the user '$username': $($_.Exception.Message)" "Gagal membuat/memperbarui user '$username': $($_.Exception.Message)"
}
# S-1-5-32-544 = Administrators, S-1-5-32-555 = Remote Desktop Users. One of them is enough to sign in over RDP.
$inAdmins = Add-KzLocalGroupMember -Sid 'S-1-5-32-544' -Name $username
$inRdpUsers = Add-KzLocalGroupMember -Sid 'S-1-5-32-555' -Name $username
if (-not ($inAdmins -or $inRdpUsers)) {
    Stop-Kz "User '$username' could not be added to Administrators or Remote Desktop Users." "User '$username' gagal ditambahkan ke Administrators maupun Remote Desktop Users."
}
Stop-KzGroup

# ---- 2) Remote Desktop (critical) ---------------------------------------------
Start-KzGroup 'Enable Remote Desktop' 'Aktifkan Remote Desktop'
try {
    $ts = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
    Set-ItemProperty -Path $ts -Name 'fDenyTSConnections' -Value 0
    $nla = if ($env:KZ_RDP_NLA -eq 'false') { 0 } else { 1 }                                  # NLA stays enabled unless explicitly turned off
    Set-ItemProperty -Path "$ts\WinStations\RDP-Tcp" -Name 'UserAuthentication' -Value $nla
    if ($nla -eq 0) { Write-KzWarn 'Network Level Authentication is OFF (nla=false). Only use this over Tailscale.' 'Network Level Authentication MATI (nla=false). Pakai hanya lewat Tailscale.' }
    Set-Service -Name TermService -StartupType Automatic
    Restart-Service -Name TermService -Force -WarningAction SilentlyContinue
} catch {
    Stop-Kz "Could not enable Remote Desktop: $($_.Exception.Message)" "Gagal mengaktifkan Remote Desktop: $($_.Exception.Message)"
}

[void](Invoke-KzOptional 'Built-in Remote Desktop firewall rules' {
    Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction Stop
})
[void](Invoke-KzOptional 'Firewall rule for port 3389' {
    if (-not (Get-NetFirewallRule -DisplayName 'Kazama RDP' -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName 'Kazama RDP' -Direction Inbound -Protocol TCP -LocalPort 3389 -Action Allow -ErrorAction Stop | Out-Null
    }
})
Stop-KzGroup

# ---- 3) keep the machine awake (optional) -------------------------------------
# Some VM images have no sleep states, and powercfg then reports an error that is harmless here.
Start-KzGroup 'Keep the machine awake' 'Jaga mesin tetap menyala'
[void](Invoke-KzOptional 'powercfg: monitor timeout' { powercfg /change monitor-timeout-ac 0 })
[void](Invoke-KzOptional 'powercfg: standby timeout' { powercfg /change standby-timeout-ac 0 })
Stop-KzGroup

# ---- 4) verify ----------------------------------------------------------------
Start-KzGroup 'Verify RDP' 'Verifikasi RDP'
$ok = $false
foreach ($i in 1..15) {
    if ((Test-NetConnection -ComputerName 127.0.0.1 -Port 3389 -WarningAction SilentlyContinue).TcpTestSucceeded) { $ok = $true; break }
    Start-Sleep -Seconds 2
}
if (-not $ok) { Stop-Kz "RDP service is not listening on port 3389." "Layanan RDP tidak mendengarkan di port 3389." }
Stop-KzGroup

$warnings = Get-KzWarnCount
$nlaText = if ($nla -eq 1) { "NLA enabled" } else { "NLA disabled" }
Write-KzInfo "RDP is ready on port 3389 ($nlaText), $warnings warning(s)" "RDP siap di port 3389 ($nlaText), $warnings peringatan"
