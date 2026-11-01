# ============================================================
# Kazama Wallpaper — applies the Kazama desktop wallpaper once per user
# Developer  : @kazamaofficial-git
# ============================================================
# Runs at every logon (scheduled task) but only changes the wallpaper the first time,
# so a user who picks another wallpaper later keeps their choice.
[CmdletBinding()]
param()
$ErrorActionPreference = 'SilentlyContinue'

$image = 'C:\Kazama\wallpaper.png'
$flagDir = Join-Path $env:APPDATA 'Kazama'
$flag = Join-Path $flagDir 'wallpaper.done'

if (-not (Test-Path $image) -or (Test-Path $flag)) { exit 0 }

$desktop = 'HKCU:\Control Panel\Desktop'
Set-ItemProperty -Path $desktop -Name 'Wallpaper' -Value $image
Set-ItemProperty -Path $desktop -Name 'WallpaperStyle' -Value '10'   # Fill
Set-ItemProperty -Path $desktop -Name 'TileWallpaper' -Value '0'

Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class KzWallpaper {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int action, int param, string path, int flags);
}
'@
# SPI_SETDESKWALLPAPER (20), update + broadcast (3)
[void][KzWallpaper]::SystemParametersInfo(20, 0, $image, 3)

New-Item -ItemType Directory -Force -Path $flagDir | Out-Null
New-Item -ItemType File -Force -Path $flag | Out-Null
