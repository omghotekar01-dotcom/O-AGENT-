@echo off
setlocal
cd /d "%~dp0"
title O-AGENT - AI provider settings
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\windows\configure-ai.ps1"
if errorlevel 1 echo AI provider update failed; review the error above.
echo.
pause
endlocal
