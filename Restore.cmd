@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title Windows Network Repair Pro - Restore
powershell.exe -NoLogo -NoProfile -Command "$id=[Security.Principal.WindowsIdentity]::GetCurrent();$p=New-Object -TypeName Security.Principal.WindowsPrincipal -ArgumentList $id;if($p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){exit 0}else{exit 1}"
if errorlevel 1 (
    set "WNR_DIR=%~dp0"
    set "WNR_SCRIPT=%~dp0Restore.ps1"
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath 'powershell.exe' -Verb RunAs -WorkingDirectory $env:WNR_DIR -ArgumentList ('-NoLogo -NoProfile -ExecutionPolicy Bypass -File ' + [char]34 + $env:WNR_SCRIPT + [char]34)"
    exit /b
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Restore.ps1"
pause
