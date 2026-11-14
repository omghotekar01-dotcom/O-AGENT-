@echo off
setlocal
title O-AGENT - Private Pilot
cd /d "%~dp0"
echo ==========================================
echo       O-AGENT PRIVATE PILOT START
echo ==========================================
echo.
echo This starter runs LOCAL services on your PC.
echo It never publishes your pilot to the public Internet.
echo.
where node >nul 2>nul
if errorlevel 1 (
  echo [FIX] Node.js 22.12+ is missing. Install Node.js, then retry.
  goto :failed
)
node -e "const [a,b]=process.versions.node.split('.').map(Number);process.exit(a>22||(a===22&&b>=12)?0:1)"
if errorlevel 1 (
  echo [FIX] Node.js 22.12 or newer is required.
  goto :failed
)
where docker >nul 2>nul
if errorlevel 1 (
  echo [FIX] Docker CLI is missing. Install and open Docker Desktop.
  goto :failed
)
docker compose version >nul 2>nul
if errorlevel 1 (
  echo [FIX] Docker Compose is not ready. Start Docker Desktop.
  goto :failed
)
where tailscale >nul 2>nul
if errorlevel 1 (
  echo [FIX] Tailscale CLI not found. Install Tailscale and sign in.
  goto :failed
)
if not exist "deploy\saas\free-pilot\start.mjs" (
  echo [FIX] Pilot source is incomplete. Extract the FULL branch ZIP.
  goto :failed
)
pushd "deploy\saas\free-pilot"
node start.mjs
set "START_RESULT=%errorlevel%"
echo.
echo ==========================================
echo        O-AGENT DIAGNOSTIC REPORT
echo ==========================================
node doctor.mjs
set "DOCTOR_RESULT=%errorlevel%"
popd
if not "%START_RESULT%"=="0" goto :failed
if not "%DOCTOR_RESULT%"=="0" goto :failed
echo.
echo [READY] Local prerequisite checks passed.
echo Open the PRIVATE HTTPS Tailnet address printed above on your phone.
echo Sign in, change your temporary owner password, and enable MFA.
echo Next, double-click CONNECT-O-AGENT-WORKER.cmd.
goto :end
:failed
echo.
echo [NOT READY] Read the [FIX] message. Do not post passwords or logs.
echo No APK build was requested.
:end
echo.
pause
endlocal
