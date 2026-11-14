@echo off
setlocal
cd /d "%~dp0"
title O-AGENT - One-time laptop remote-control permission
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\windows\configure-one-tap-control.ps1"
if errorlevel 1 (
  echo Configuration did not complete. Review the message above.
)
echo.
pause
endlocal
