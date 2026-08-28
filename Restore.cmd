@echo off
setlocal
cd /d "%~dp0"
title Windows Network Repair Pro - Restore
net session >nul 2>&1
if not "%errorlevel%"=="0" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~dp0Restore.ps1' -Verb RunAs -WorkingDirectory '%~dp0'"
    exit /b
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Restore.ps1"
pause
