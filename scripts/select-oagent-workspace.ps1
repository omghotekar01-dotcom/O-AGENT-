$ErrorActionPreference = 'Stop'
$mutex = $null
$ownsLock = $false
try {
  # Prevent two accidental double-clicks from starting duplicate trusted workers.
  $mutex = [System.Threading.Mutex]::new($false, 'Local\OAgentPrivatePilotWorker')
  try { $ownsLock = $mutex.WaitOne(0) }
  catch [System.Threading.AbandonedMutexException] { $ownsLock = $true }
  if (-not $ownsLock) {
    Write-Host '[READY] Trusted O-AGENT worker is already active in another window.'
    Write-Host 'Use the existing worker window; no duplicate was started.'
    exit 0
  }

  Set-Location -LiteralPath (Split-Path -Parent $PSScriptRoot)
  $repo = (Get-Location).Path
  $worker = Join-Path $repo 'apps\saas-worker\src\quickstart.mjs'
  $pilot = Join-Path $repo 'deploy\saas\free-pilot\.env.local'
  if (-not (Test-Path -LiteralPath $worker -PathType Leaf)) {
    throw 'Full source tree missing. Pull the complete development branch.'
  }
  if (-not (Test-Path -LiteralPath $pilot -PathType Leaf)) {
    throw 'Private pilot is not initialized. Double-click START-O-AGENT.cmd.'
  }
  $node = Get-Command node -ErrorAction SilentlyContinue
  if (-not $node) { throw 'Node.js 22.12+ is required.' }
  $v = & node -p 'process.versions.node'
  if ($LASTEXITCODE -ne 0 -or [version]$v -lt [version]'22.12.0') {
    throw 'Upgrade Node.js to version 22.12 or newer.'
  }

  $settings = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'OAgent' }
              else { Join-Path $env:USERPROFILE 'AppData\Local\OAgent' }
  $savedPath = Join-Path $settings 'trusted-workspace.txt'
  $folder = $null
  if ($env:OAGENT_CHANGE_WORKSPACE -ne '1' -and
      (Test-Path -LiteralPath $savedPath -PathType Leaf)) {
    $previous = (Get-Content -LiteralPath $savedPath -Raw -Encoding UTF8).Trim()
    if ($previous -and (Test-Path -LiteralPath $previous -PathType Container)) {
      $folder = (Resolve-Path -LiteralPath $previous).Path
      Write-Host '[PASS] Reusing your previously approved project folder.'
    } else {
      Write-Host '[SETUP] Saved project folder is no longer available; choose a folder.'
    }
  }

  if (-not $folder) {
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = 'Select ONE trusted project folder for O-AGENT (first setup only)'
    $dialog.ShowNewFolderButton = $false
    try {
      $choice = $dialog.ShowDialog()
      if ($choice -ne [System.Windows.Forms.DialogResult]::OK) {
        throw 'No trusted folder chosen. Nothing was enrolled. Double-click START-O-AGENT.cmd again.'
      }
      $folder = (Resolve-Path -LiteralPath $dialog.SelectedPath).Path
    } finally { $dialog.Dispose() }
    New-Item -ItemType Directory -Path $settings -Force | Out-Null
    Set-Content -LiteralPath $savedPath -Value $folder -Encoding UTF8 -NoNewline
    Write-Host '[PASS] Saved your trusted project folder for the next startup.'
  }

  Write-Host ('[WORKER] Project: ' + $folder)
  Write-Host '[WORKER] Keep this window open while working from your phone.'
  Write-Host '[WORKER] First enrollment: approve the exact fingerprint in O-AGENT > Devices.'
  & node $worker $folder
  if ($LASTEXITCODE -ne 0) {
    throw 'Worker exited with an error. See the worker message above; existing data was preserved.'
  }
} catch {
  Write-Host ('[FIX] ' + $_.Exception.Message)
  exit 1
} finally {
  if ($mutex) {
    if ($ownsLock) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
  }
}
