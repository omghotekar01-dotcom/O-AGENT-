@echo off
setlocal
cd /d "%~dp0"
title O-AGENT - Install official native AI SDKs
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\windows\install-native-agent-sdks.ps1"
if errorlevel 1 (
  echo.
  echo Native SDK setup did not complete. Review the message above.
)
echo.
pause
endlocal
