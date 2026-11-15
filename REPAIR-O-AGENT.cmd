@echo off
setlocal
title O-AGENT - Safe Windows Pilot Recovery
cd /d "%~dp0"
echo ================================================
echo   O-AGENT PRIVATE PILOT - SAFE RECOVERY
echo ================================================
echo.
echo Preserve the existing Tailscale routes:
echo    HTTPS 443  -^> localhost:8000 (other app)
echo    HTTPS 8443 -^> localhost:8787 (O-AGENT)
echo.
echo This tool NEVER resets Tailscale or deletes database volumes.
echo It will back up both databases before changing pilot credentials
echo or the saved OIDC redirect. All backups are encrypted.
echo.
if not exist "deploy\saas\free-pilot\repair-db-auth.mjs" goto :missing
pushd "deploy\saas\free-pilot"
set "IN_PILOT=1"
echo [1/5] Diagnose O-AGENT database role credentials...
node repair-db-auth.mjs
if errorlevel 1 goto :failed
echo.
echo This recovery will modify ONLY O-AGENT database role passwords
echo that do not match this pilot's saved secrets, and the oagent-web
echo OAuth redirect to the existing HTTPS 8443 endpoint.
echo.
choice /c YN /n /m "Proceed with verified encrypted backups first? [Y/N]: "
if errorlevel 2 goto :cancelled
echo.
echo [2/5] Back up both databases and reconcile role credentials...
node repair-db-auth.mjs --apply
if errorlevel 1 goto :failed
echo.
echo [3/5] Recreate Keycloak with the reconciled database credentials...
docker compose --env-file .env.local -f compose.yaml up -d --no-deps --force-recreate identity
if errorlevel 1 goto :failed
echo.
echo [4/5] Verify and migrate the EXISTING HTTPS 8443 OIDC address...
node migrate-existing-port.mjs 8443
if errorlevel 1 goto :failed
node migrate-existing-port.mjs 8443 --apply
if errorlevel 1 goto :failed
echo.
echo [5/5] Start O-AGENT without changing Tailscale routes...
node start.mjs
if errorlevel 1 goto :failed
node doctor.mjs
if errorlevel 1 goto :failed
echo.
echo [READY] O-AGENT private gateway and login diagnostics passed.
echo Open the private HTTPS :8443 address printed above on your tailnet phone.
goto :end
:missing
echo [FIX] This branch is missing the repair scripts. Pull latest GitHub files.
goto :end
:failed
echo.
echo [FIX] Recovery stopped at the first failed check.
echo Leave the Docker volumes and private backup files untouched.
echo Do not post passwords, .env.local, or full Keycloak token logs.
goto :end
:cancelled
echo.
echo [SAFE] Nothing was changed by this repair wizard.
:end
if defined IN_PILOT popd
echo.
pause
endlocal
