# ============================================================
# Kazama Windows - optional Chocolatey packages (GitHub Actions mode)
# Developer  : @kazamaofficial-git
# ============================================================
# Reads : KZ_PACKAGES  (comma/space separated, e.g. "googlechrome,vscode")
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Kazama.psm1') -Force

$list = @(($env:KZ_PACKAGES -split '[,\s]+') | Where-Object { $_ })
if ($list.Count -eq 0) { Write-KzInfo "No extra packages requested" "Tidak ada paket tambahan"; return }

$choco = Get-KzChoco
foreach ($pkg in $list) {
    if ($pkg -notmatch '^[a-z0-9][a-z0-9.\-]*$') {
        Write-KzWarn "Skipping invalid package name '$pkg'" "Melewati nama paket tidak valid '$pkg'"
        continue
    }
    Write-KzInfo "Installing $pkg ..." "Memasang $pkg ..."
    & $choco install $pkg -y --no-progress --limit-output 2>&1 | ForEach-Object { Write-Host "$_" }
    if ($LASTEXITCODE -notin 0, 1641, 3010) {
        Write-KzWarn "Package $pkg failed (exit $LASTEXITCODE)" "Paket $pkg gagal (exit $LASTEXITCODE)"
    }
}
$global:LASTEXITCODE = 0
