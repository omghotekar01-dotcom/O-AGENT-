# Runs on Windows CI with Windows PowerShell 5.1.
$ErrorActionPreference = 'Stop'
foreach ($item in @('common.ps1', 'setup.ps1', 'start.ps1', 'stop.ps1', 'configure-projects.ps1', 'enable-remote.ps1')) {
    $path = Join-Path $PSScriptRoot $item
    $tokens = $null
    $errors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) { throw "PowerShell parser rejected $($item): $($errors[0])" }
}
. "$PSScriptRoot\common.ps1"

$work = Join-Path $env:TEMP ("oagent-launch-test-" + [guid]::NewGuid().ToString('N'))
$env:OAGENT_HOME = Join-Path $work 'secrets'
$env:OAGENT_NO_BROWSER = '1'
$env:OAGENT_SKIP_ADB = '1'
$env:OAGENT_SKIP_SHORTCUT = '1'
$env:OAGENT_PORT = '19583'
New-Item -ItemType Directory -Path $env:OAGENT_HOME -Force | Out-Null
$apiToken = ([Guid]::NewGuid().ToString('N') + [Guid]::NewGuid().ToString('N'))
$workerToken = ([Guid]::NewGuid().ToString('N') + [Guid]::NewGuid().ToString('N'))
$apiSecure = ConvertTo-SecureString -String $apiToken -AsPlainText -Force
$workerSecure = ConvertTo-SecureString -String $workerToken -AsPlainText -Force
try {
    Save-OAgentConfig ([ordered]@{
        Version = 1
        ApiTokenEncrypted = (ConvertFrom-SecureString -SecureString $apiSecure)
        WorkerTokenEncrypted = (ConvertFrom-SecureString -SecureString $workerSecure)
        AiKeyEncrypted = ''
        Provider = 'none'
        Model = ''
        WorkerId = 'test-machine'
        Workspace = $work
    })
} finally {
    $apiSecure.Dispose()
    $workerSecure.Dispose()
}
$stored = Get-Content -LiteralPath (Get-OAgentConfigPath) -Raw
if ($stored.Contains($apiToken) -or $stored.Contains($workerToken)) {
    throw 'Plaintext secret found in stored config.'
}
if ((Unlock-OAgentSecret (Read-OAgentConfig).ApiTokenEncrypted) -cne $apiToken) {
    throw 'Encrypted operator token did not survive a round trip.'
}
try {
    & "$PSScriptRoot\start.ps1"
    $one = Get-OAgentPidState
    if (-not $one.BackendPid -or -not $one.WorkerPid) { throw 'Missing process IDs.' }

    # A second click must not spawn duplicate backend/worker processes.
    & "$PSScriptRoot\start.ps1"
    $two = Get-OAgentPidState
    if ($one.BackendPid -ne $two.BackendPid -or $one.WorkerPid -ne $two.WorkerPid) {
        throw 'Second click started duplicate backend/worker.'
    }

    $headers = @{ Authorization = "Bearer $apiToken" }
    $machineState = Invoke-RestMethod -Uri 'http://127.0.0.1:19583/api/state' -Headers $headers
    if (@($machineState.workers | Where-Object { $_.id -eq 'test-machine' -and $_.status -eq 'online' }).Count -ne 1) {
        throw 'Machine did not register as online in the real backend.'
    }
    $ai = Invoke-RestMethod -Uri 'http://127.0.0.1:19583/api/ai/status' -Headers $headers
    if ($ai.configured -ne $false) { throw 'Unconfigured AI provider was falsely marked ready.' }
    Write-Host 'Windows launcher integration tests passed.' -ForegroundColor Green
} finally {
    & "$PSScriptRoot\stop.ps1"
    Start-Sleep -Milliseconds 500
    if (Test-OAgentPort 19583) { throw 'Stop did not close backend port.' }
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
