@echo off
setlocal
cd /d "%~dp0"

fltmc >nul 2>&1
if not "%errorlevel%"=="0" (
    echo Requesting Administrator privileges...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0NetworkRepair.ps1"
set "RC=%errorlevel%"
echo.
if not "%RC%"=="0" echo Application exited with code %RC%.
pause
exit /b %RC%
