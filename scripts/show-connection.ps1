# ============================================================
# Kazama Windows - print connection details (log + job summary)
# Developer  : @kazamaofficial-git
# ============================================================
# Reads : KZ_HOST, KZ_NAME, KZ_USERNAME, KZ_WINDOWS, KZ_DURATION
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Kazama.psm1') -Force

$user = $env:KZ_USERNAME
$addr = $env:KZ_HOST
$title = T 'Kazama Windows RDP is ready' 'Kazama Windows RDP siap'
$steps = T @"
1. Make sure **Tailscale** is running on your device and signed in to the same tailnet.
2. Open **Windows App** > **+ > PC** and set **PC name** to:  ``$addr``  (or ``$($env:KZ_NAME)``)
3. **User account** > *Add user account*:  username ``$user``  ·  password = your ``RDP_PASSWORD``.
4. Save, connect, and accept the certificate prompt.
"@ @"
1. Pastikan **Tailscale** aktif di perangkat Anda dan masuk ke tailnet yang sama.
2. Buka **Windows App** > **+ > PC**, isi **PC name** dengan:  ``$addr``  (atau ``$($env:KZ_NAME)``)
3. **User account** > *Add user account*:  username ``$user``  ·  password = ``RDP_PASSWORD`` Anda.
4. Simpan, hubungkan, dan setujui peringatan sertifikat.
"@
$ending = T "This session lasts at most **$($env:KZ_DURATION) minutes**. Cancel the workflow run to stop it earlier. Everything on this machine is erased when it ends." `
            "Sesi ini berlangsung maksimal **$($env:KZ_DURATION) menit**. Batalkan workflow run untuk menghentikan lebih awal. Semua data di mesin ini terhapus saat sesi berakhir."

Add-KzSummary @"
## 🖥️ $title

| | |
|---|---|
| **Windows** | ``$($env:KZ_WINDOWS)`` |
| **Address (Tailscale)** | ``$addr`` |
| **Username** | ``$user`` |

$steps

$ending

— *Kazama · @kazamaofficial-git*
"@

Write-Host ''
Write-Host '=============================================='
Write-Host " $title"
Write-Host "   PC name  : $addr"
Write-Host "   Username : $user"
Write-Host '   Password : RDP_PASSWORD'
Write-Host '=============================================='
