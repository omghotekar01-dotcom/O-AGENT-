[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"

$config = Read-OAgentConfig
Write-Host ''
Write-Host 'O-AGENT - connect real project sources' -ForegroundColor Cyan
Write-Host 'Your saved operator, worker and model-provider credentials will not change.'
Write-Host 'Stop O-AGENT before editing sources. Restart afterward.'
Write-Host ''

$currentRepos = 'omghotekar01-dotcom/O-AGENT-'
if (($config.PSObject.Properties.Name -contains 'GitHubRepos') -and $config.GitHubRepos) {
  $currentRepos = $config.GitHubRepos
}
$repos = Read-Host "GitHub repository list, comma-separated [$currentRepos]"
if ([string]::IsNullOrWhiteSpace($repos)) { $repos = $currentRepos }
$specs = @($repos.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($specs.Count -gt 8) { throw 'At most 8 GitHub repositories are supported for this development build.' }
foreach ($spec in $specs) {
  if ($spec -notmatch '^[a-zA-Z0-9_.-]{1,100}/[a-zA-Z0-9_.-]{1,100}$') {
    throw "Invalid repo identifier: $spec. Use owner/repository, not a URL."
  }
}
$config | Add-Member -NotePropertyName 'GitHubRepos' -NotePropertyValue ($specs -join ',') -Force

Write-Host ''
Write-Host 'Private GitHub repos need a separate fine-grained GitHub token with read access.'
Write-Host 'Public repositories do not require a token.'
$changeToken = Read-Host 'Add or replace a GitHub token? [y/N]'
if ($changeToken -match '^[yY]') {
  $secret = Read-Host 'Paste fine-grained GitHub token (hidden)' -AsSecureString
  try {
    $value = if ($secret.Length -gt 0) { ConvertFrom-SecureString -SecureString $secret } else { '' }
    $config | Add-Member -NotePropertyName 'GitHubTokenEncrypted' -NotePropertyValue $value -Force
  } finally { $secret.Dispose() }
}

Write-Host ''
Write-Host 'Codex Cloud can report YOUR task metadata via the official CLI if you have installed and signed in to Codex on this laptop.'
Write-Host 'It does NOT mirror ChatGPT Work chats or browser screens. Sync sends task titles/status/URLs to your O-AGENT backend.'
$enabled = Read-Host 'Opt in to Codex Cloud task sync? [y/N]'
$config | Add-Member -NotePropertyName 'CodexEnabled' -NotePropertyValue ($enabled -match '^[yY]') -Force

Write-Host ''
Write-Host 'IMPORTANT: Codex CLI / IDE project history is different from Codex Cloud tasks.' -ForegroundColor Cyan
Write-Host 'It lists saved Codex CLI and IDE sessions on THIS Windows account, grouped by project folder.'
Write-Host 'This sends working-directory names and short session previews to your private local O-AGENT backend.'
Write-Host 'Your full transcript, credentials and auth files are NOT uploaded by this connector.'
$localDefault = 'N'
if (($config.PSObject.Properties.Name -contains 'CodexLocalEnabled') -and $config.CodexLocalEnabled) { $localDefault = 'Y' }
$local = Read-Host "Sync MY local Codex CLI / IDE projects? [y/N] (previous: $localDefault)"
if ([string]::IsNullOrWhiteSpace($local)) {
  $localEnabled = $localDefault -eq 'Y'
} else {
  $localEnabled = $local -match '^[yY]'
}
$config | Add-Member -NotePropertyName 'CodexLocalEnabled' -NotePropertyValue $localEnabled -Force
Save-OAgentConfig $config

Write-Host ''
Write-Host 'Saved new integration settings. Restart O-AGENT to activate.' -ForegroundColor Green
Write-Host 'To authorize Codex CLI once, run: codex login'
Write-Host 'To inspect available Codex tasks: codex cloud list --json --limit 20'

Write-Host 'Codex CLI / IDE sessions will appear on the phone after the next successful worker sync, even if Codex Cloud tasks are empty.' -ForegroundColor Cyan
