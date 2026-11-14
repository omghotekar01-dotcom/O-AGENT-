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

# Stop only the trusted visible O-AGENT remote helper belonging to this user.
try {
    $helperScript = Join-Path $PSScriptRoot 'remote-control.ps1'
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -and
            $_.CommandLine.IndexOf($helperScript, [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
            $_.CommandLine.IndexOf('-Trusted', [StringComparison]::OrdinalIgnoreCase) -ge 0
        } | ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }
} catch { Write-Host 'Close the O-AGENT control helper if it is still visible.' -ForegroundColor Yellow }

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
