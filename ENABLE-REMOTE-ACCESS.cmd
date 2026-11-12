@echo off
setlocal
cd /d "%~dp0"
title O-AGENT - Private remote access
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\windows\enable-remote.ps1"
if errorlevel 1 echo Remote access was not enabled. Check the message above.
echo.
pause
endlocal
