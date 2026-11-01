# ============================================================
# Kazama Windows - leave the tailnet and collect optional files
# Developer  : @kazamaofficial-git
# ============================================================
# Reads : KZ_USERNAME, KZ_SAVE_FILES ('true' copies Desktop + Documents for upload)
[CmdletBinding()]
param()
$ErrorActionPreference = 'Continue'
Import-Module (Join-Path $PSScriptRoot 'Kazama.psm1') -Force

$ts = 'C:\Program Files\Tailscale\tailscale.exe'
if (Test-Path $ts) { & $ts logout 2>$null | Out-Null }

if ($env:KZ_SAVE_FILES -eq 'true') {
    $dest = Join-Path $env:RUNNER_TEMP 'kazama-files'
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    foreach ($folder in 'Desktop', 'Documents') {
        $src = "C:\Users\$($env:KZ_USERNAME)\$folder"
        if (Test-Path $src) { Copy-Item -Path $src -Destination (Join-Path $dest $folder) -Recurse -Force -ErrorAction SilentlyContinue }
    }
    Write-KzInfo "Desktop and Documents collected for upload" "Desktop dan Documents dikumpulkan untuk diunggah"
}
Write-KzInfo "Cleanup done - session ended" "Pembersihan selesai - sesi berakhir"
exit 0
