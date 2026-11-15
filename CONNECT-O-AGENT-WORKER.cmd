@echo off
setlocal
title O-AGENT - Advanced: Change Trusted Project Folder
cd /d "%~dp0"
echo ============================================
echo    O-AGENT ADVANCED WORKER FOLDER SELECTION
echo ============================================
echo.
echo Normal use: double-click START-O-AGENT.cmd ONLY.
echo This advanced option changes the saved trusted project folder.
echo Stop your existing O-AGENT worker first before switching folders.
echo.
where powershell >nul 2>nul
if errorlevel 1 (
  echo [FIX] Windows PowerShell is unavailable.
  goto :end
)
set "OAGENT_CHANGE_WORKSPACE=1"
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0scripts\select-oagent-workspace.ps1"
if errorlevel 1 echo [FIX] Worker did not start. Read the message above.
:end
echo.
pause
endlocal
