[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"
$config = Read-OAgentConfig

$packages = @()
if (($config.PSObject.Properties.Name -contains 'ClaudeSdkEnabled') -and
    $config.ClaudeSdkEnabled -eq $true) {
  $packages += '@anthropic-ai/claude-agent-sdk@0.3.322'
}
if (($config.PSObject.Properties.Name -contains 'CopilotSdkEnabled') -and
    $config.CopilotSdkEnabled -eq $true) {
  $packages += '@github/copilot-sdk@1.0.30'
}

Write-Host ''
Write-Host 'O-AGENT - install authorized official agent SDK packages' -ForegroundColor Cyan
Write-Host 'This optional step installs official SDK packages into the local O-AGENT folder.'
Write-Host 'It does not install browser extensions, access your AI chats, sign into accounts,'
Write-Host 'submit prompts, or grant any remote access without your consent.'
if ($packages.Count -eq 0) {
  Write-Host 'No native SDK provider enabled. Run CONFIGURE-PROJECTS.cmd first.' -ForegroundColor Yellow
  return
}
Write-Host ''
Write-Host ('Packages: ' + ($packages -join ', ')) -ForegroundColor Cyan
Write-Host 'Provider sign-in is separate. Package installation alone does not mean connected.'
Write-Host 'Only install packages from sources you trust on a computer you own.'
$confirm = Read-Host 'Type INSTALL to continue, or press Enter to cancel'
if ($confirm -cne 'INSTALL') { Write-Host 'No packages installed.'; return }

$npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
if (-not $npm) { throw 'npm is missing. Install Node.js 22+ from its official website.' }
$root = Get-OAgentRepo
Push-Location -LiteralPath $root
try {
  # npm receives an explicit, audited fixed list. No secrets or arbitrary
  # script snippets are passed as arguments. No package-lock/source change.
  & $npm.Source install --no-save --no-package-lock --omit=dev --no-audit -- @packages
  if ($LASTEXITCODE -ne 0) {
    throw 'Native SDK package installation failed. Read npm errors above. The existing O-AGENT launcher is unaffected.'
  }
  Write-Host 'SDK installation completed. Sign in with each official provider, then restart O-AGENT.' -ForegroundColor Green
} finally {
  Pop-Location
}
