# Requires Windows PowerShell 5.1 and the same signed-in Windows user as O-AGENT.
# Called only after explicit permission in the local VS Code extension.
# The worker token is emitted once over private child-process stdout and
# immediately stored in VS Code SecretStorage. NEVER log or print it in UI.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
try {
    if (-not $env:LOCALAPPDATA) { throw 'Local app data is unavailable.' }
    $path = Join-Path $env:LOCALAPPDATA 'OAgent\settings.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw 'O-AGENT Windows setup has not been completed.'
    }
    $settings = Get-Content -LiteralPath $path -Encoding UTF8 -Raw | ConvertFrom-Json
    if ($settings.Version -ne 1 -or
        [string]::IsNullOrWhiteSpace($settings.WorkerTokenEncrypted)) {
        throw 'O-AGENT Windows settings are incomplete.'
    }
    # Use only the persisted local port, never a remote address or user-provided URL.
    $port = 8787
    $processFile = Join-Path $env:LOCALAPPDATA 'OAgent\processes.json'
    if (Test-Path -LiteralPath $processFile -PathType Leaf) {
        $processState = Get-Content -LiteralPath $processFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($processState.Port -and [int]$processState.Port -ge 1024 -and
            [int]$processState.Port -le 65535) {
            $port = [int]$processState.Port
        }
    }
    $secure = ConvertTo-SecureString -String $settings.WorkerTokenEncrypted
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        $token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
        if ([string]::IsNullOrEmpty($token) -or $token.Length -lt 24 -or
            $token.Length -gt 512) { throw 'Worker token is invalid.' }
        $result = @{ origin = "http://127.0.0.1:$port"; workerToken = $token } |
            ConvertTo-Json -Compress
        [Console]::Out.WriteLine($result)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
        $secure.Dispose()
        $token = $null
    }
} catch {
    # No exception details; provider/DPAPI exceptions may contain sensitive data.
    [Console]::Error.WriteLine('O-AGENT local enrollment is unavailable. Run O-AGENT.cmd using the same Windows account.')
    exit 1
}
