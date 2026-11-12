@echo off
setlocal
cd /d "%~dp0"
title O-AGENT - Project connections
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\windows\configure-projects.ps1"
if errorlevel 1 (
  echo Configuration failed. Review the error above.
)
echo.
pause
endlocal
