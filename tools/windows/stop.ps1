[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"

$state = Get-OAgentPidState
if (-not $state) {
    Write-Host 'No O-AGENT launcher processes recorded.'
    return
}
$root = Get-OAgentRepo
$worker = Join-Path $root 'apps\gateway\src\worker.mjs'
$backend = Join-Path $root 'apps\control-plane\src\server.mjs'

foreach ($item in @(
    @{ Pid = [int]$state.WorkerPid; Script = $worker; Label = 'laptop gateway' },
    @{ Pid = [int]$state.BackendPid; Script = $backend; Label = 'backend' }
)) {
    if (Test-OAgentOwnedProcess $item.Pid $item.Script) {
        Stop-Process -Id $item.Pid -Force -ErrorAction Stop
        Write-Host "Stopped $($item.Label)." -ForegroundColor Green
    } else {
        Write-Host "$($item.Label) already stopped or no longer owned by the launcher."
    }
}
Remove-Item -LiteralPath (Join-Path (Get-OAgentHome) 'processes.json') -Force -ErrorAction SilentlyContinue
Write-Host 'O-AGENT stopped. Credentials remain protected for the next one-click start.'
