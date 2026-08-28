@echo off
setlocal
cd /d "%~dp0"

title Windows Network Repair Pro

:: UAC elevation
net session >nul 2>&1
if not "%errorlevel%"=="0" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~dp0NetworkRepair.ps1' -Verb RunAs -WorkingDirectory '%~dp0'"
    exit /b
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0NetworkRepair.ps1"
set "RC=%errorlevel%"
if not "%RC%"=="0" (
    echo.
    echo [ERROR] Network Repair exited with code %RC%.
    pause
)
exit /b %RC%
