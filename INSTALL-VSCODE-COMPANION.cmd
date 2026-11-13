@echo off
setlocal
cd /d "%~dp0"
title O-AGENT - Install VS Code Companion (NOT Visual Studio)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\windows\install-vscode-companion.ps1" %*
echo.
pause
endlocal
