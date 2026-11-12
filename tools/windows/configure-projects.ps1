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
Save-OAgentConfig $config

Write-Host ''
Write-Host 'Saved new integration settings. Restart O-AGENT to activate.' -ForegroundColor Green
Write-Host 'To authorize Codex CLI once, run: codex login'
Write-Host 'To inspect available Codex tasks: codex cloud list --json --limit 20'
