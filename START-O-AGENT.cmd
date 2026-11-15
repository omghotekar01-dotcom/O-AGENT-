@echo off
setlocal EnableExtensions
title O-AGENT - One Click Mission Control
cd /d "%~dp0"
echo.
echo ================================================
echo   O-AGENT - ONE CLICK PRIVATE MISSION CONTROL
echo ================================================
echo.
where node >nul 2>nul
if errorlevel 1 (
  echo [FIX] Install Node.js 22.12 or newer, then double-click this same file again.
  goto :end
)
node -e "const [a,b]=process.versions.node.split('.').map(Number);process.exit(a>22||(a===22&&b>=12)?0:1)"
if errorlevel 1 (
  echo [FIX] Update Node.js to version 22.12 or newer.
  goto :end
)
if not exist "scripts\one-click-pilot.mjs" (
  echo [FIX] Complete project files are missing. Pull the full O-AGENT development branch.
  goto :end
)
node "scripts\one-click-pilot.mjs"
if errorlevel 1 (
  echo.
  echo [NOT READY] Follow the [FIX] message above.
  echo Do not delete your Docker data or private .env.local settings.
) else (
  echo.
  echo [INFO] You may run this same file again when your worker is stopped.
)
:end
echo.
pause
endlocal
