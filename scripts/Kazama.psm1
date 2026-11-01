# ============================================================
# Kazama Windows - shared PowerShell module (GitHub Actions mode)
# Developer  : @kazamaofficial-git
# Repository : https://github.com/kazamaofficial-git/kazama-windows
# ============================================================
Set-StrictMode -Version Latest

$script:Lang = if ($env:KZ_LANG -eq 'id') { 'id' } else { 'en' }

function T {
    param([Parameter(Mandatory)][string]$En, [Parameter(Mandatory)][string]$Id)
    if ($script:Lang -eq 'id') { $Id } else { $En }
}

function Write-KzInfo {
    param([Parameter(Mandatory)][string]$En, [Parameter(Mandatory)][string]$Id)
    Write-Host ('[kazama] ' + (T $En $Id))
}

function Write-KzWarn {
    param([Parameter(Mandatory)][string]$En, [Parameter(Mandatory)][string]$Id)
    Write-Host ('::warning::[kazama] ' + (T $En $Id))
}

function Stop-Kz {
    param([Parameter(Mandatory)][string]$En, [Parameter(Mandatory)][string]$Id)
    Write-Host ('::error::[kazama] ' + (T $En $Id))
    exit 1
}

function Set-KzOutput {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Value)
    if ($env:GITHUB_OUTPUT) { Add-Content -Path $env:GITHUB_OUTPUT -Value "$Name=$Value" -Encoding utf8 }
}

function Add-KzSummary {
    param([Parameter(Mandatory)][string]$Markdown)
    if ($env:GITHUB_STEP_SUMMARY) { Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $Markdown -Encoding utf8 }
}

function Get-KzChoco {
    $cmd = Get-Command choco -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return 'C:\ProgramData\chocolatey\bin\choco.exe'
}

function Get-KzSecret {
    <# Prefers the Actions SECRET; falls back to the repository VARIABLE (plain text) with a warning. #>
    param([Parameter(Mandatory)][string]$Name)
    $secret = [Environment]::GetEnvironmentVariable($Name)
    if ($secret) { return $secret }
    $variable = [Environment]::GetEnvironmentVariable("${Name}_VAR")
    if ($variable) {
        Write-KzWarn "$Name was read from a repository VARIABLE (not masked). Move it to Secrets." `
                     "$Name dibaca dari VARIABLE repository (tidak disamarkan). Pindahkan ke Secrets."
        Write-Host "::add-mask::$variable"
        return $variable
    }
    return $null
}

Export-ModuleMember -Function T, Write-KzInfo, Write-KzWarn, Stop-Kz, Set-KzOutput, Add-KzSummary, Get-KzChoco, Get-KzSecret
