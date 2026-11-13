[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"

$root = Get-OAgentRepo
$homeDir = Get-OAgentHome
New-Item -ItemType Directory -Path $homeDir -Force | Out-Null
if (-not (Test-Path -LiteralPath (Get-OAgentConfigPath))) {
    Write-Host 'First launch: configure credentials once.' -ForegroundColor Cyan
    & "$PSScriptRoot\setup.ps1"
}
$config = Read-OAgentConfig
$node = Get-OAgentNode

$port = 8787
if ($env:OAGENT_PORT) { $port = [int]$env:OAGENT_PORT }
if ($port -lt 1024 -or $port -gt 65535) { throw 'Invalid OAGENT_PORT.' }
$baseUrl = "http://127.0.0.1:$port"
$backendScript = Join-Path $root 'apps\control-plane\src\server.mjs'
$workerScript = Join-Path $root 'apps\gateway\src\worker.mjs'

$apiToken = Unlock-OAgentSecret $config.ApiTokenEncrypted
$workerToken = Unlock-OAgentSecret $config.WorkerTokenEncrypted
if ($apiToken.Length -lt 24 -or $workerToken.Length -lt 24 -or $apiToken -ceq $workerToken) {
    throw 'Saved tokens are invalid. Re-run CONFIGURE-O-AGENT.cmd.'
}

$logDir = Join-Path $homeDir 'logs'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

$old = Get-OAgentPidState
$backendPid = 0
$workerPid = 0
if ($old) {
    if (Test-OAgentOwnedProcess ([int]$old.BackendPid) $backendScript) { $backendPid = [int]$old.BackendPid }
    if (Test-OAgentOwnedProcess ([int]$old.WorkerPid) $workerScript) { $workerPid = [int]$old.WorkerPid }
}

# Reusing a manually started server would make token mismatches confusing.
if ($backendPid -eq 0 -and (Test-OAgentPort $port)) {
    throw "Port $port is already in use. Close your OLD Terminal 1 (npm start), then double-click O-AGENT again. Nothing was stopped or overwritten."
}

$startedBackend = $false
$startedWorker = $false
try {
    $env:HOST = '127.0.0.1'
    $env:PORT = [string]$port
    $env:OAGENT_SERVER_URL = $baseUrl
    $env:OAGENT_API_TOKEN = $apiToken
    $env:OAGENT_WORKER_TOKEN = $workerToken
    $env:OAGENT_DATA_FILE = Join-Path $root '.local\oagent-data.json'
    # Secure persistent BYOK vault master key, DPAPI-wrapped for this Windows
    # account. This is generated only once, never printed or committed.
    if (-not (($config.PSObject.Properties.Name -contains 'VaultKeyEncrypted') -and $config.VaultKeyEncrypted)) {
        $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
        $bytes = New-Object byte[] 32
        try { $rng.GetBytes($bytes) }
        finally { $rng.Dispose() }
        $secretText = [Convert]::ToBase64String($bytes)
        [Array]::Clear($bytes, 0, $bytes.Length)
        $secure = ConvertTo-SecureString -String $secretText -AsPlainText -Force
        try {
            $config | Add-Member -NotePropertyName 'VaultKeyEncrypted' -NotePropertyValue (ConvertFrom-SecureString -SecureString $secure) -Force
        } finally { $secure.Dispose(); $secretText = $null }
        Save-OAgentConfig $config
    }
    $env:OAGENT_VAULT_KEY_BASE64 = Unlock-OAgentSecret $config.VaultKeyEncrypted
    $env:OAGENT_WORKER_ID = $config.WorkerId
    $env:OAGENT_WORKSPACE_ROOT = $config.Workspace

    Remove-Item Env:OPENAI_API_KEY, Env:ANTHROPIC_API_KEY, Env:GEMINI_API_KEY -ErrorAction SilentlyContinue
    if ($config.AiKeyEncrypted) {
        if ($config.Provider -eq 'openai') { $env:OPENAI_API_KEY = Unlock-OAgentSecret $config.AiKeyEncrypted }
        elseif ($config.Provider -eq 'anthropic') { $env:ANTHROPIC_API_KEY = Unlock-OAgentSecret $config.AiKeyEncrypted }
        elseif ($config.Provider -eq 'gemini') { $env:GEMINI_API_KEY = Unlock-OAgentSecret $config.AiKeyEncrypted }
    }
    $env:OAGENT_AI_PROVIDER = $config.Provider
    $env:OAGENT_AI_MODEL = $config.Model
    # GitHub public repository updates are readable without a token.
    $env:OAGENT_GITHUB_REPOS = if (($config.PSObject.Properties.Name -contains 'GitHubRepos' -and $config.GitHubRepos)) { $config.GitHubRepos } else { 'omghotekar01-dotcom/O-AGENT-' }
    $env:OAGENT_ENABLE_CODEX_LOCAL_SYNC = if (($config.PSObject.Properties.Name -contains 'CodexLocalEnabled') -and $config.CodexLocalEnabled) { '1' } else { '0' }
    $env:OAGENT_ENABLE_CODEX_CLOUD_SYNC = if (($config.PSObject.Properties.Name -contains 'CodexEnabled' -and $config.CodexEnabled)) { '1' } else { '0' }
    Remove-Item Env:OAGENT_GITHUB_TOKEN -ErrorAction SilentlyContinue
    if (($config.PSObject.Properties.Name -contains 'GitHubTokenEncrypted') -and $config.GitHubTokenEncrypted) {
        $env:OAGENT_GITHUB_TOKEN = Unlock-OAgentSecret $config.GitHubTokenEncrypted
    }

    if ($backendPid -eq 0) {
        Write-Host 'Starting O-AGENT backend...' -ForegroundColor Cyan
        $startArgs = @{
            FilePath = $node
            ArgumentList = ('"' + $backendScript + '"')
            WorkingDirectory = $root
            PassThru = $true
            WindowStyle = 'Hidden'
            RedirectStandardOutput = (Join-Path $logDir 'backend.stdout.log')
            RedirectStandardError = (Join-Path $logDir 'backend.stderr.log')
        }
        $process = Start-Process @startArgs
        $backendPid = $process.Id
        $startedBackend = $true
    } else {
        Write-Host "Backend already running (PID $backendPid)." -ForegroundColor Green
    }

    $ready = $false
    for ($attempt = 0; $attempt -lt 35; $attempt++) {
        try {
            $health = Invoke-RestMethod -Uri "$baseUrl/health" -Method Get -TimeoutSec 2
            if ($health.status -eq 'ok' -and $health.service -eq 'oagent-control-plane') {
                $ready = $true
                break
            }
        } catch { Start-Sleep -Milliseconds 350 }
    }
    if (-not $ready) { throw "Backend failed to start; inspect $logDir\backend.stderr.log." }

    # Verify the operator token against the actual backend before starting a worker.
    $headers = @{ Authorization = "Bearer $apiToken" }
    try { $null = Invoke-RestMethod -Uri "$baseUrl/api/state" -Headers $headers -TimeoutSec 5 }
    catch { throw 'Backend token did not match saved operator token. Stop old server and reconfigure if needed.' }

    # Only the backend needs operator/provider keys. Do not pass them to the gateway.
    Remove-Item Env:OAGENT_API_TOKEN, Env:OPENAI_API_KEY, Env:ANTHROPIC_API_KEY, Env:GEMINI_API_KEY, Env:OAGENT_GITHUB_TOKEN, Env:OAGENT_VAULT_KEY_BASE64 -ErrorAction SilentlyContinue
    if ($workerPid -eq 0) {
        $otherWorkers = @(Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -and (
                $_.CommandLine.IndexOf('apps/gateway/src/worker.mjs', [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
                $_.CommandLine.IndexOf('apps\gateway\src\worker.mjs', [StringComparison]::OrdinalIgnoreCase) -ge 0
            ) })
        if ($otherWorkers.Count -gt 0) {
            throw 'An old manual gateway appears to be running. Close Terminal 2 (npm run worker), then click O-AGENT again.'
        }
        Write-Host 'Starting laptop gateway...' -ForegroundColor Cyan
        $startArgs = @{
            FilePath = $node
            ArgumentList = ('"' + $workerScript + '"')
            WorkingDirectory = $root
            PassThru = $true
            WindowStyle = 'Hidden'
            RedirectStandardOutput = (Join-Path $logDir 'worker.stdout.log')
            RedirectStandardError = (Join-Path $logDir 'worker.stderr.log')
        }
        $process = Start-Process @startArgs
        $workerPid = $process.Id
        $startedWorker = $true
    } else {
        Write-Host "Gateway already running (PID $workerPid)." -ForegroundColor Green
    }

    $online = $false
    for ($attempt = 0; $attempt -lt 35; $attempt++) {
        try {
            $state = Invoke-RestMethod -Uri "$baseUrl/api/state" -Headers $headers -TimeoutSec 4
            if (@($state.workers | Where-Object { $_.id -eq $config.WorkerId -and $_.status -eq 'online' }).Count -gt 0) {
                $online = $true
                break
            }
        } catch { }
        Start-Sleep -Milliseconds 500
    }
    if (-not $online) { throw "Worker did not register as online. Check $logDir\worker.stderr.log." }
    Save-OAgentPidState $backendPid $workerPid $port

    Write-Host ""
    Write-Host 'O-AGENT is ONLINE.' -ForegroundColor Green
    Write-Host "  Web dashboard: $baseUrl"
    Write-Host "  Laptop: $($config.WorkerId) - online"
    try {
        $ai = Invoke-RestMethod -Uri "$baseUrl/api/ai/status" -Headers $headers -TimeoutSec 3
        if ($ai.configured) {
            Write-Host "  AI: $($ai.provider) / $($ai.model) (configured; test a chat)"
        } else {
            Write-Host '  AI: not configured; configure later'
        }
    } catch { Write-Host '  AI: provider status unavailable.' }

    # Phone needs USB debugging and authorization once.
    if ($env:OAGENT_SKIP_ADB -ne '1') {
        $adb = Get-OAgentAdb
        if ($adb) {
            $lines = @(& $adb devices 2>$null)
            $device = $lines | Where-Object { $_ -match "^\S+\s+device\s*$" } | Select-Object -First 1
            if ($device) {
                & $adb reverse tcp:$port tcp:$port | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "  Phone USB bridge: READY (use $baseUrl in Android)" -ForegroundColor Green
                }
            } else {
                Write-Host '  Phone not detected: connect via USB, then double-click O-AGENT again.' -ForegroundColor Yellow
            }
        } else {
            Write-Host '  ADB not found: web works; install Android Platform-Tools for phone bridging.' -ForegroundColor Yellow
        }
    }
    Write-Host "  Logs: $logDir"
    Write-Host '  To stop: double-click STOP-O-AGENT.cmd'
    if ($env:OAGENT_NO_BROWSER -ne '1') { Start-Process $baseUrl }
} catch {
    # Only terminate processes created by this particular failed launch.
    if ($startedWorker -and (Test-OAgentOwnedProcess $workerPid $workerScript)) {
        Stop-Process -Id $workerPid -Force -ErrorAction SilentlyContinue
    }
    if ($startedBackend -and (Test-OAgentOwnedProcess $backendPid $backendScript)) {
        Stop-Process -Id $backendPid -Force -ErrorAction SilentlyContinue
    }
    throw
} finally {
    Remove-Item Env:OAGENT_API_TOKEN, Env:OAGENT_WORKER_TOKEN, Env:OPENAI_API_KEY, Env:ANTHROPIC_API_KEY, Env:OAGENT_GITHUB_TOKEN -ErrorAction SilentlyContinue
    $apiToken = $null
    $workerToken = $null
}
