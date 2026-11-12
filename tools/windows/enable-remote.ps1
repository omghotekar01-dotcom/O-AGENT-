[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"

$tail = Get-Command tailscale.exe -ErrorAction SilentlyContinue
if (-not $tail) {
  $known = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
  if (-not (Test-Path -LiteralPath $known)) {
    throw 'Tailscale is not installed. Install it from https://tailscale.com/download/windows and sign in.'
  }
  $tail = @{ Source = $known }
}
Write-Host 'Tailscale private network connection:' -ForegroundColor Cyan
& $tail.Source status
if ($LASTEXITCODE -ne 0) { throw 'Sign in to Tailscale on both Windows and Android first.' }
if (-not (Test-OAgentPort 8787)) { throw 'Start O-AGENT.cmd first; the backend must be listening on localhost:8787.' }

Write-Host ''
Write-Host 'Tailscale Serve publishes only to authenticated devices in YOUR tailnet.'
Write-Host 'It does NOT use Funnel or open your laptop to the public internet.'
$ok = Read-Host 'Enable HTTPS Serve for your laptop backend? Type YES'
if ($ok -cne 'YES') { Write-Host 'No settings changed.'; return }
Write-Host 'If Windows asks for administrator permission, accept only if you trust this action.'
& $tail.Source serve --bg 8787
if ($LASTEXITCODE -ne 0) { throw 'Tailscale Serve failed. Review the message above, sign in or enable HTTPS certificates, then retry in an Administrator terminal.' }
& $tail.Source serve status
Write-Host ''
Write-Host 'On Android: install/sign in to Tailscale with the SAME tailnet, then use the https://...ts.net URL printed above as the O-AGENT Backend URL.' -ForegroundColor Green
Write-Host 'You can keep USB disconnected. The laptop must still be online for local work.'
Write-Host 'To disable remote access: tailscale serve --https=443 off'
