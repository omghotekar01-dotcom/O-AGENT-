@echo off
setlocal
cd /d "%~dp0"
title O-AGENT - Start
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\windows\start.ps1"
if errorlevel 1 (
  echo.
  echo O-AGENT could not start. Read the error above and retry.
  pause
) else (
  echo.
  echo Backend and laptop gateway are running. You may close this window.
  timeout /t 8 >nul
)
endlocal
