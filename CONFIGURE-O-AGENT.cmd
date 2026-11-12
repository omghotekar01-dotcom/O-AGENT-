@echo off
setlocal
cd /d "%~dp0"
title O-AGENT - One-time setup
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\windows\setup.ps1" -Force
if errorlevel 1 echo Setup failed. Existing configuration is not modified if saving was not reached.
echo.
pause
endlocal
