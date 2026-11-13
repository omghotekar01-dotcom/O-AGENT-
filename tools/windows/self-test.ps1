# Runs on Windows CI with Windows PowerShell 5.1.
$ErrorActionPreference = 'Stop'
foreach ($item in @('common.ps1', 'setup.ps1', 'start.ps1', 'stop.ps1', 'configure-projects.ps1', 'configure-ai.ps1', 'enable-remote.ps1', 'remote-control.ps1')) {
    $path = Join-Path $PSScriptRoot $item
    $tokens = $null
    $errors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) { throw "PowerShell parser rejected $($item): $($errors[0])" }
}
# Compile the Win32 input helper without injecting any mouse/keyboard
# events. Native INPUT must be 40 bytes on Windows x64.
$inputScript = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'remote-control.ps1') -Raw
$pattern = "(?s)Add-Type -TypeDefinition @'\r?\n(.*?)\r?\n'@ -ErrorAction Stop"
$match = [regex]::Match($inputScript, $pattern)
if (-not $match.Success) { throw 'Could not locate Win32 helper type definition.' }
Add-Type -TypeDefinition $match.Groups[1].Value -ErrorAction Stop
if ([Environment]::Is64BitProcess -and [OAgentUserInput]::InputStructSize() -ne 40) {
    throw 'Incorrect 64-bit Win32 INPUT marshaling size'
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
    $account = Invoke-RestMethod -Uri 'http://127.0.0.1:19583/api/me' -Headers $headers
    if ($account.role -ne 'owner' -or $account.vaultReady -ne $true) {
        throw 'Windows one-click launcher did not initialize the per-account credential vault.'
    }
    $protected = Read-OAgentConfig
    if (-not $protected.VaultKeyEncrypted -or $protected.VaultKeyEncrypted.Length -lt 60) {
        throw 'Encrypted BYOK vault key was not saved for this Windows account.'
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
