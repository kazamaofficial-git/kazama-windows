# ============================================================
# Kazama Windows - shared PowerShell module (GitHub Actions mode)
# Developer  : @kazamaofficial-git
# Repository : https://github.com/kazamaofficial-git/kazama-windows
# ============================================================
Set-StrictMode -Version Latest

$script:Lang = if ($env:KZ_LANG -eq 'id') { 'id' } else { 'en' }
$script:WarnCount = 0

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
    $script:WarnCount++
    Write-Host ('::warning::[kazama] ' + (T $En $Id))
}

function Get-KzWarnCount { $script:WarnCount }

function Start-KzGroup {
    <# Folds the following log lines under a title in the GitHub Actions log. #>
    param([Parameter(Mandatory)][string]$En, [Parameter(Mandatory)][string]$Id)
    Write-Host ('::group::' + (T $En $Id))
}

function Stop-KzGroup { Write-Host '::endgroup::' }

function Invoke-KzOptional {
    <# Runs a NON-critical step. Any failure (cmdlet error, non-zero exit code, native stderr) becomes ONE
       yellow warning that names the step - never red text, never a stopped job. Returns $true on success. #>
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][scriptblock]$Action)
    try {
        $global:LASTEXITCODE = 0
        $text = (& $Action 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -ne 0) {
            $first = ($text -split "`r?`n" | Select-Object -First 1)
            Write-KzWarn "$Name returned exit code ${LASTEXITCODE}: $first (continuing)" "$Name mengembalikan exit code ${LASTEXITCODE}: $first (dilanjutkan)"
            return $false
        }
        return $true
    } catch {
        Write-KzWarn "$Name failed: $($_.Exception.Message) (continuing)" "$Name gagal: $($_.Exception.Message) (dilanjutkan)"
        return $false
    } finally {
        $global:LASTEXITCODE = 0
    }
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

function Set-KzLocalUser {
    <# Creates the local user or resets its password. Uses ADSI (WinNT provider) instead of the LocalAccounts cmdlets:
       those run through a compatibility layer in PowerShell 7 and also apply a display-name check to the password.
       Falls back to net.exe. Returns 'created' or 'updated'; throws with BOTH error messages when everything fails. #>
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Password)

    $adsiError = $null
    try {
        $computer = [ADSI]"WinNT://$env:COMPUTERNAME,computer"
        $existing = @($computer.Children | Where-Object { $_.SchemaClassName -eq 'User' -and $_.Name -eq $Name })
        if ($existing.Count -gt 0) { $user = $existing[0]; $state = 'updated' }
        else { $user = $computer.Create('User', $Name); $state = 'created' }

        $user.SetPassword($Password)
        $user.SetInfo()
        $flags = [int]$user.UserFlags.Value
        $user.Put('UserFlags', (($flags -bor 0x10000) -band (-bnot 0x2)))   # password never expires, account enabled
        $user.Put('Description', 'Kazama RDP')
        $user.Put('PasswordExpired', 0)                                       # never force a change at first logon (NLA would reject it)
        $user.SetInfo()
        return $state
    } catch {
        $adsiError = '{0} (0x{1:X8}): {2}' -f $_.Exception.GetType().Name, $_.Exception.HResult, $_.Exception.Message
    }

    $netError = $null
    $null = & net.exe user $Name 2>&1
    if ($LASTEXITCODE -eq 0) { $state = 'updated'; $out = & net.exe user $Name $Password 2>&1 | Out-String }
    else { $state = 'created'; $out = & net.exe user $Name $Password /add /y 2>&1 | Out-String }
    if ($LASTEXITCODE -eq 0) { return $state }
    $netError = ($out -replace '\s+', ' ').Trim()
    throw "ADSI: $adsiError | net user: $netError"
}

function Add-KzLocalGroupMember {
    <# Adds a local user to a built-in group identified by SID (names are localized on non-English Windows).
       'Already a member' counts as success. Returns $true / $false. #>
    param([Parameter(Mandatory)][string]$Sid, [Parameter(Mandatory)][string]$Name)

    $groupName = ((New-Object Security.Principal.SecurityIdentifier($Sid)).Translate([Security.Principal.NTAccount]).Value -split '\\')[-1]
    try {
        ([ADSI]"WinNT://$env:COMPUTERNAME/$groupName,group").Add("WinNT://$env:COMPUTERNAME/$Name,user")
        return $true
    } catch {
        if ($_.Exception.Message -match 'already') { return $true }
    }
    $out = & net.exe localgroup $groupName $Name /add 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0 -or $out -match 'already') { return $true }
    Write-KzWarn "Could not add '$Name' to group '$groupName': $(($out -replace '\s+', ' ').Trim())" "Gagal menambahkan '$Name' ke grup '$groupName': $(($out -replace '\s+', ' ').Trim())"
    return $false
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

Export-ModuleMember -Function Set-KzLocalUser, Add-KzLocalGroupMember, T, Write-KzInfo, Write-KzWarn, Get-KzWarnCount, Start-KzGroup, Stop-KzGroup, Invoke-KzOptional, Stop-Kz, Set-KzOutput, Add-KzSummary, Get-KzChoco, Get-KzSecret
