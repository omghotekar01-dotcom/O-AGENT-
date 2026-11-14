$ErrorActionPreference = 'Stop'
try {
  Set-Location -LiteralPath (Split-Path -Parent $PSScriptRoot)
  $repo = (Get-Location).Path
  $worker = Join-Path $repo 'apps\saas-worker\src\quickstart.mjs'
  $pilot = Join-Path $repo 'deploy\saas\free-pilot\.env.local'
  if (-not (Test-Path -LiteralPath $worker -PathType Leaf)) {
    throw 'Full source tree missing. Extract the complete development ZIP.'
  }
  if (-not (Test-Path -LiteralPath $pilot -PathType Leaf)) {
    throw 'Pilot not configured. Double-click START-O-AGENT.cmd first.'
  }
  $node = Get-Command node -ErrorAction SilentlyContinue
  if (-not $node) { throw 'Node.js 22.12+ is required.' }
  $v = & node -p 'process.versions.node'
  if ($LASTEXITCODE -ne 0 -or [version]$v -lt [version]'22.12.0') {
    throw 'Upgrade Node.js to version 22.12 or newer.'
  }
  Add-Type -AssemblyName System.Windows.Forms
  $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
  $dialog.Description = 'Choose the trusted project folder O-AGENT may inspect'
  $dialog.ShowNewFolderButton = $false
  $result = $dialog.ShowDialog()
  if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
    Write-Host 'No project selected. Nothing was connected.'
    exit 0
  }
  $folder = (Resolve-Path -LiteralPath $dialog.SelectedPath).Path
  Write-Host ('Selected trusted workspace: ' + $folder)
  Write-Host 'Approve the displayed device fingerprint in your signed-in phone dashboard.'
  Write-Host 'Do not close this window while you want the worker online.'
  & node $worker $folder
  exit $LASTEXITCODE
} catch {
  Write-Host ('[FIX] ' + $_.Exception.Message)
  exit 1
}
