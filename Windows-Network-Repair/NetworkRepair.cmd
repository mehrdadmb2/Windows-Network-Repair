@echo off
title Windows Network Repair Utility
:: بررسی دسترسی مدیر سیستم
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting Administrator privileges...
    powershell start-process -verb runas '%0'
    exit /b
)
cd /d "%~dp0"
powershell -ExecutionPolicy Bypass -File "NetworkRepair.ps1"
pause