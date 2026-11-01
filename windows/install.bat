@echo off
rem Kazama - runs once at the end of the Windows install (dockur copies this folder to C:\OEM)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0kazama-setup.ps1" -RunNow >> "C:\Kazama-install.log" 2>&1
exit /b 0
