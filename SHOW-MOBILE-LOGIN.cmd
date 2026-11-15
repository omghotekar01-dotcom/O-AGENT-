@echo off
setlocal
title O-AGENT - Native Phone Sign-in
cd /d "%~dp0"
echo.
where node >nul 2>nul
if errorlevel 1 (
  echo [FIX] Node.js is not available. Install Node.js 22.12+ and run START-O-AGENT.cmd first.
  goto :end
)
node "scripts\show-mobile-login.mjs"
:end
echo.
pause
endlocal
