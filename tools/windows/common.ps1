# Windows PowerShell 5.1 compatible helpers. Load using: . "$PSScriptRoot\common.ps1"
Set-StrictMode -Version Latest

function Get-OAgentRepo {
    return (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

function Get-OAgentHome {
    if ($env:OAGENT_HOME) { return $env:OAGENT_HOME }
    return (Join-Path $env:LOCALAPPDATA 'OAgent')
}

function Get-OAgentConfigPath {
    return (Join-Path (Get-OAgentHome) 'settings.json')
}

function Read-OAgentConfig {
    $path = Get-OAgentConfigPath
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Setup is missing. Run O-AGENT.cmd to configure your account once."
    }
    $settings = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($settings.Version -ne 1 -or -not $settings.ApiTokenEncrypted -or -not $settings.WorkerTokenEncrypted) {
        throw "O-AGENT local settings are incomplete. Run CONFIGURE-O-AGENT.cmd."
    }
    return $settings
}

function Unlock-OAgentSecret([string]$ciphertext) {
    if ([string]::IsNullOrWhiteSpace($ciphertext)) { return '' }
    # ConvertTo-SecureString uses Windows DPAPI for the current Windows user.
    $secure = ConvertTo-SecureString -String $ciphertext
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
        $secure.Dispose()
    }
}

function Save-OAgentConfig($config) {
    $homeDir = Get-OAgentHome
    New-Item -ItemType Directory -Path $homeDir -Force | Out-Null
    $path = Get-OAgentConfigPath
    $json = $config | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText($path, $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-OAgentNode {
    $command = Get-Command node.exe -ErrorAction SilentlyContinue
    if (-not $command) { throw "Node.js not found. Install Node.js 22 or later: https://nodejs.org/" }
    $versionText = & $command.Source --version
    $major = [int]([regex]::Match($versionText, '^v(\d+)').Groups[1].Value)
    if ($major -lt 22) { throw "Node.js 22 or later is required; found $versionText." }
    return $command.Source
}

function Test-OAgentPort([int]$port) {
    $socket = New-Object Net.Sockets.TcpClient
    try {
        $async = $socket.BeginConnect('127.0.0.1', $port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne(400, $false)) { return $false }
        $socket.EndConnect($async)
        return $true
    } catch {
        return $false
    } finally {
        $socket.Close()
    }
}

function Test-OAgentOwnedProcess([int]$processId, [string]$scriptPath) {
    if ($processId -le 0) { return $false }
    $p = Get-CimInstance Win32_Process -Filter "ProcessId = $processId" -ErrorAction SilentlyContinue
    if (-not $p) { return $false }
    if ($p.Name -ne 'node.exe') { return $false }
    # The launcher starts node with an absolute script path to prevent PID reuse.
    return ($null -ne $p.CommandLine -and
        $p.CommandLine.IndexOf($scriptPath, [StringComparison]::OrdinalIgnoreCase) -ge 0)
}

function Get-OAgentPidState {
    $path = Join-Path (Get-OAgentHome) 'processes.json'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try { return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json) }
    catch { return $null }
}

function Save-OAgentPidState([int]$backendPid, [int]$workerPid, [int]$port) {
    $path = Join-Path (Get-OAgentHome) 'processes.json'
    [IO.File]::WriteAllText($path,
        (@{ BackendPid=$backendPid; WorkerPid=$workerPid; Port=$port; StartedAt=(Get-Date).ToString('o') } | ConvertTo-Json),
        (New-Object System.Text.UTF8Encoding($false)))
}

function Get-OAgentAdb {
    $candidate = Get-Command adb.exe -ErrorAction SilentlyContinue
    if ($candidate) { return $candidate.Source }
    foreach ($path in @(
        (Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'),
        (Join-Path $HOME 'Android\platform-tools\adb.exe')
    )) {
        if (Test-Path -LiteralPath $path) { return $path }
    }
    return $null
}
