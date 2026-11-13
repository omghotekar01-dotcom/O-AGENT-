[CmdletBinding()]
param([string]$VsixPath = '')
$ErrorActionPreference = 'Stop'

# Windows associates .vsix with Visual Studio's installer on some machines.
# O-AGENT's companion is a VS CODE extension, so install through code.cmd.
$codeCandidates = New-Object 'System.Collections.Generic.List[string]'
foreach ($name in @('code.cmd', 'code.exe')) {
    $command = Get-Command $name -ErrorAction SilentlyContinue
    if ($command -and $command.Source) { $codeCandidates.Add($command.Source) }
}
if ($env:LOCALAPPDATA) {
    $codeCandidates.Add((Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\bin\code.cmd'))
}
if ($env:ProgramFiles) {
    $codeCandidates.Add((Join-Path $env:ProgramFiles 'Microsoft VS Code\bin\code.cmd'))
}
$code = $codeCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $code) {
    Write-Host 'Visual Studio CODE command-line launcher not found.' -ForegroundColor Yellow
    Write-Host 'Open Visual Studio Code (blue icon) > Extensions (Ctrl+Shift+X) > ... > Install from VSIX...'
    Write-Host 'Do NOT double-click the .vsix file: Windows routes it to Visual Studio 2022/2026.'
    exit 1
}

if (-not $VsixPath) {
    $default = Join-Path (Join-Path $HOME 'Downloads') 'o-agent-vscode-companion-vsix\o-agent-vscode-companion.vsix'
    if (Test-Path -LiteralPath $default -PathType Leaf) {
        $VsixPath = $default
    } else {
        $VsixPath = (Read-Host 'Paste the full path to o-agent-vscode-companion.vsix').Trim('"').Trim()
    }
}
if (-not (Test-Path -LiteralPath $VsixPath -PathType Leaf) -or
    ([IO.Path]::GetExtension($VsixPath) -ne '.vsix')) {
    Write-Host 'VSIX file was not found. Download/extract the official GitHub Actions VSIX artifact first.' -ForegroundColor Red
    exit 1
}
$VsixPath = (Resolve-Path -LiteralPath $VsixPath).Path
Write-Host "Installing O-AGENT companion in Visual Studio Code: $code" -ForegroundColor Cyan
& $code --install-extension "$VsixPath" --force
if ($LASTEXITCODE -ne 0) {
    Write-Host 'VS Code rejected the extension. Confirm you installed Visual Studio Code, not Visual Studio.' -ForegroundColor Red
    exit 1
}
Write-Host 'VS Code extension installer completed.' -ForegroundColor Green
Write-Host 'Open VS Code, Ctrl+Shift+P, search for O-AGENT: Configure Secure Companion.'
