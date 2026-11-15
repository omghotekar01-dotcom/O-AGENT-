@echo off
setlocal
cd /d "%~dp0"
where node >nul 2>nul
if errorlevel 1 (
  echo Node.js 22.12 or newer is required. Install Node.js before starting O-AGENT.
  exit /b 1
)
node start.mjs
if errorlevel 1 (
  echo O-AGENT pilot could not start. Run: node doctor.mjs
  exit /b 1
)
echo To view private status again: node doctor.mjs
endlocal
