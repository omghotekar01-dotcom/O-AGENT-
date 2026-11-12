@echo off
setlocal
cd /d "%~dp0"
title O-AGENT - Stop
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\windows\stop.ps1"
echo.
pause
endlocal
