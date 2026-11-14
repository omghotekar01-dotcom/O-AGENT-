@echo off
setlocal
title O-AGENT - Trusted Workspace Connection
cd /d "%~dp0"
echo ==========================================
echo      O-AGENT TRUSTED WORKSPACE SETUP
echo ==========================================
echo.
echo Start the private pilot FIRST, then sign in on your phone.
echo Choose only a project folder you own and trust.
echo Pairing requires explicit approval in the signed-in dashboard.
echo.
where powershell >nul 2>nul
if errorlevel 1 (
  echo [FIX] Windows PowerShell is unavailable.
  goto :end
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\select-oagent-workspace.ps1"
if errorlevel 1 echo [FIX] Worker could not start. Review the message above.
:end
echo.
pause
endlocal
