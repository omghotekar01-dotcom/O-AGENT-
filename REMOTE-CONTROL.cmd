@echo off
setlocal
cd /d "%~dp0"
title O-AGENT - EXPLICIT REMOTE CONTROL - CLOSE TO STOP
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\windows\remote-control.ps1"
echo.
echo Remote input companion has ended.
pause
endlocal
