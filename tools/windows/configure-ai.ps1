[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"
$config = Read-OAgentConfig
Write-Host ''
Write-Host 'O-AGENT - Change ONLY your AI provider' -ForegroundColor Cyan
Write-Host 'Your existing operator token, worker token, Tailscale, GitHub and Codex settings will be preserved.'
Write-Host 'STOP-O-AGENT.cmd first, then restart O-AGENT.cmd after saving.'
Write-Host "Current provider: $($config.Provider) / $($config.Model)"
Write-Host ''
Write-Host '1 OpenAI API | 2 Anthropic Claude API | 3 Disable O-AGENT AI chat | 4 Google Gemini API'
$selection = Read-Host 'Choose provider [Enter keeps current]'
$provider = $config.Provider
if (-not [string]::IsNullOrWhiteSpace($selection)) {
    switch ($selection.Trim()) {
        '1' { $provider = 'openai' }
        '2' { $provider = 'anthropic' }
        '3' { $provider = 'none' }
        '4' { $provider = 'gemini' }
        default { throw 'Select 1, 2, 3, 4 or press Enter to keep current.' }
    }
}
$defaults = @{ openai = 'gpt-5.6-terra'; anthropic = 'claude-sonnet-4-5'; gemini = 'gemini-2.5-flash' }
$model = ''
$cipher = ''
if ($provider -ne 'none') {
    $existing = ($provider -eq $config.Provider)
    $default = if ($existing -and $config.Model) { $config.Model } else { $defaults[$provider] }
    $model = Read-Host "Model ID [$default]"
    if ([string]::IsNullOrWhiteSpace($model)) { $model = $default } else { $model = $model.Trim() }
    if ($model.Length -lt 2 -or $model.Length -gt 120 -or $model -notmatch '^[A-Za-z0-9._:/-]+$') {
        throw 'Invalid model identifier.'
    }
    $cipher = if ($existing -and $config.AiKeyEncrypted) { $config.AiKeyEncrypted } else { '' }
    if ($cipher) {
        $replace = Read-Host 'Replace the existing encrypted AI key? [y/N]'
        if ($replace -match '^[yY]') { $cipher = '' }
    }
    if (-not $cipher) {
        $secure = Read-Host "$provider API key (hidden; blank leaves AI unconfigured)" -AsSecureString
        try {
            if ($secure.Length -gt 0) {
                $cipher = ConvertFrom-SecureString -SecureString $secure
            }
        } finally { $secure.Dispose() }
    }
}
$config | Add-Member -NotePropertyName 'Provider' -NotePropertyValue $provider -Force
$config | Add-Member -NotePropertyName 'Model' -NotePropertyValue $model -Force
$config | Add-Member -NotePropertyName 'AiKeyEncrypted' -NotePropertyValue $cipher -Force
Save-OAgentConfig $config
Write-Host ''
Write-Host "AI provider saved: $provider / $model" -ForegroundColor Green
Write-Host 'Other O-AGENT tokens, source connections and Tailscale settings were not changed.'
Write-Host 'Restart O-AGENT.cmd. Real API billing and provider authorization must be checked with a model request.'
