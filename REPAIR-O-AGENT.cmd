@echo off
setlocal
title O-AGENT - Recover incomplete first start
cd /d "%~dp0"
echo =======================================================
echo   O-AGENT - SAFE FIRST-START RECOVERY (PORT 8787)
echo =======================================================
echo.
echo Existing routes are preserved:
echo HTTPS 443  -^> localhost:8000  (other app)
echo HTTPS 8443 -^> localhost:8787 (O-AGENT)
echo.
echo No Docker volume will be removed and Tailscale will not be reset.
echo This tool diagnoses missing PostgreSQL roles/databases, encrypts
echo backups BEFORE changes, and then repairs the private login URL.
echo.
if not exist "deploy\saas\free-pilot\bootstrap-db.mjs" goto :missing
pushd "deploy\saas\free-pilot"
set "IN_PILOT=1"
echo [1/8] Inspect partially initialized PostgreSQL cluster...
node bootstrap-db.mjs
if errorlevel 1 goto :failed
echo.
echo Recovery may add missing O-AGENT DB roles and databases, reconcile
echo mismatched role passwords and migrate the OAuth web redirect.
echo Only local O-AGENT settings will change. Existing data is backed up
echo with verified encryption, and recovery keys are stored separately.
echo.
choice /c YN /n /m "Allow this private-pilot repair? [Y/N]: "
if errorlevel 2 goto :cancelled
echo.
echo [2/8] Encrypt cluster backup and create ONLY missing database objects...
node bootstrap-db.mjs --apply
if errorlevel 1 goto :failed
echo.
echo [3/8] Diagnose credentials for all O-AGENT database roles...
node repair-db-auth.mjs
if errorlevel 1 goto :failed
echo.
echo [4/8] Repair mismatched credentials after encrypted database backups...
node repair-db-auth.mjs --apply
if errorlevel 1 goto :failed
echo.
echo [5/8] Start/recreate Keycloak identity with working database roles...
docker compose --env-file .env.local -f compose.yaml up -d --no-deps --force-recreate identity
if errorlevel 1 goto :failed
echo.
echo [6/8] Migrate the EXISTING OAuth web client to HTTPS 8443...
node migrate-existing-port.mjs 8443
if errorlevel 1 goto :failed
node migrate-existing-port.mjs 8443 --apply
if errorlevel 1 goto :failed
echo.
echo [7/8] Refresh saved private realm and Keycloak hostname...
rem realm-init exits immediately after copying the private realm. Compose 'up' by
rem itself stays attached even after Exit 0. Use its exit code so recovery resumes.
docker compose --env-file .env.local -f compose.yaml up --no-deps --force-recreate --exit-code-from realm-init realm-init
if errorlevel 1 goto :failed
docker compose --env-file .env.local -f compose.yaml up -d --no-deps --force-recreate identity
if errorlevel 1 goto :failed
echo.
echo [8/8] Start API and private gateway, then check all services...
node start.mjs
if errorlevel 1 goto :failed
node doctor.mjs
if errorlevel 1 goto :failed
echo.
echo [READY] O-AGENT diagnostics passed.
echo Connect your phone to the tailnet and open HTTPS :8443.
goto :end
:missing
echo [FIX] Update the GitHub development branch first; bootstrap helper missing.
goto :end
:failed
echo.
echo [FIX] Recovery stopped at the first failed step.
echo Do not delete PostgreSQL volumes, clear Docker, or reset Tailscale.
echo Keep all generated encrypted backups and recovery keys private.
goto :end
:cancelled
echo.
echo [SAFE] No recovery changes were requested.
:end
if defined IN_PILOT popd
echo.
pause
endlocal
