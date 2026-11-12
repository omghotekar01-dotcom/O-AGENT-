[CmdletBinding()]
param([switch]$Force)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"

$path = Get-OAgentConfigPath
if ((Test-Path -LiteralPath $path) -and -not $Force) {
    Write-Host "O-AGENT was already configured for this Windows user." -ForegroundColor Green
    Write-Host "Use O-AGENT.cmd to start or CONFIGURE-O-AGENT.cmd to update your settings."
    return
}

function New-OAgentToken {
    $random = [Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = New-Object byte[] 32
    try { $random.GetBytes($bytes) }
    finally { $random.Dispose() }
    return ([BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
}

function Get-OAgentInputSecret([string]$description, [string]$existingValue) {
    if ($existingValue -and $existingValue.Length -ge 24) {
        $useExisting = Read-Host "Use $description from this terminal environment? [Y/n]"
        if ($useExisting -ne 'n' -and $useExisting -ne 'N') {
            $value = ConvertTo-SecureString -AsPlainText -Force $existingValue
            try { return ConvertFrom-SecureString -SecureString $value }
            finally { $value.Dispose() }
        }
    }

    $secret = Read-Host "Paste EXISTING $description (hidden; Enter generates a new one)" -AsSecureString
    if ($secret.Length -eq 0) {
        $secret.Dispose()
        $plain = New-OAgentToken
        $secret = ConvertTo-SecureString -AsPlainText -Force $plain
        Write-Host "New $description (copy privately; shown only now):" -ForegroundColor Yellow
        Write-Host $plain -ForegroundColor Yellow
        $plain = $null
    }
    if ($secret.Length -lt 24) {
        $secret.Dispose()
        throw "$description must be at least 24 characters."
    }
    try { return ConvertFrom-SecureString -SecureString $secret }
    finally { $secret.Dispose() }
}

Write-Host ""
Write-Host "  O-AGENT - One-time Windows setup" -ForegroundColor Cyan
Write-Host "  Your secrets will be encrypted with Windows DPAPI for this account."
Write-Host "  Reuse your existing operator token to keep the phone connected."
Write-Host ""
if ($Force -and (Test-Path -LiteralPath $path)) {
    $confirm = Read-Host "This replaces saved credentials. Type RECONFIGURE to continue"
    if ($confirm -cne 'RECONFIGURE') { Write-Host "No changes made."; return }
}

$operatorCipher = Get-OAgentInputSecret 'OPERATOR token' $env:OAGENT_API_TOKEN
$workerCipher = Get-OAgentInputSecret 'WORKER token' $env:OAGENT_WORKER_TOKEN

# Do not allow accidentally using the same secret for both roles.
if ($operatorCipher -eq $workerCipher) { throw "Operator and worker tokens must be different." }

$id = Read-Host 'Worker ID [my-laptop]'
if ([string]::IsNullOrWhiteSpace($id)) { $id = 'my-laptop' }
if ($id -notmatch '^[A-Za-z0-9_-]{1,100}$') { throw 'Worker ID can only contain letters, numbers, underscores and hyphens.' }

$defaultWorkspace = Join-Path $HOME 'OAGENT_TEST_WORKSPACE'
$workspace = Read-Host "Safe workspace directory [$defaultWorkspace]"
if ([string]::IsNullOrWhiteSpace($workspace)) { $workspace = $defaultWorkspace }
$workspace = [IO.Path]::GetFullPath($workspace)
New-Item -ItemType Directory -Force -Path $workspace | Out-Null

Write-Host ""
Write-Host 'AI provider: 1 OpenAI, 2 Anthropic, 3 skip for now (machine controls still work)'
$choice = Read-Host 'Choose [1]'
if ([string]::IsNullOrWhiteSpace($choice)) { $choice = '1' }
$provider = 'none'
$model = ''
$aiCipher = ''
switch ($choice) {
    '1' {
        $provider = 'openai'
        $model = 'gpt-5.6-terra'
    }
    '2' {
        $provider = 'anthropic'
        $model = 'claude-sonnet-4-5'
    }
    '3' { $provider = 'none' }
    default { throw 'Please choose 1, 2 or 3.' }
}
if ($provider -ne 'none') {
    $custom = Read-Host "Model ID [$model]"
    if (-not [string]::IsNullOrWhiteSpace($custom)) { $model = $custom.Trim() }
    if ($model.Length -gt 120 -or $model -notmatch '^[A-Za-z0-9._:/-]+$') {
        throw 'Invalid model ID.'
    }
    $apiKey = Read-Host "$provider API key (hidden; Enter skips AI for now)" -AsSecureString
    if ($apiKey.Length -gt 0) {
        try { $aiCipher = ConvertFrom-SecureString -SecureString $apiKey }
        finally { $apiKey.Dispose() }
    } else {
        $apiKey.Dispose()
        Write-Host 'AI provider not connected: you can add a key using CONFIGURE-O-AGENT.cmd later.' -ForegroundColor Yellow
    }
}

$config = [ordered]@{
    Version = 1
    ApiTokenEncrypted = $operatorCipher
    WorkerTokenEncrypted = $workerCipher
    AiKeyEncrypted = $aiCipher
    Provider = $provider
    Model = $model
    WorkerId = $id
    Workspace = $workspace
}
Save-OAgentConfig $config

# A Windows shortcut resolves even when the repository lives in a OneDrive folder.
if ($env:OAGENT_SKIP_SHORTCUT -ne '1') {
    try {
        $desktop = [Environment]::GetFolderPath('Desktop')
        if ($desktop -and (Test-Path -LiteralPath $desktop)) {
            $shell = New-Object -ComObject WScript.Shell
            $shortcut = $shell.CreateShortcut((Join-Path $desktop 'O-AGENT.lnk'))
            $shortcut.TargetPath = (Join-Path (Get-OAgentRepo) 'O-AGENT.cmd')
            $shortcut.WorkingDirectory = Get-OAgentRepo
            $shortcut.Description = 'Start O-AGENT local backend, worker and phone bridge'
            $shortcut.Save()
            Write-Host 'Desktop shortcut created: O-AGENT' -ForegroundColor Green
        }
    } catch {
        Write-Host 'Desktop shortcut could not be created; O-AGENT.cmd still works.' -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host 'Setup saved securely for this Windows user.' -ForegroundColor Green
Write-Host "Settings: $path"
Write-Host "Workspace: $workspace"
Write-Host 'Next time, just double-click O-AGENT on your desktop.'
