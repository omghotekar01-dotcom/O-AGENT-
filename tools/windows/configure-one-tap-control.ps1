[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"

$config = Read-OAgentConfig
$active = (($config.PSObject.Properties.Name -contains 'RemoteControlTrusted') -and $config.RemoteControlTrusted -eq $true)
Write-Host ''
Write-Host 'O-AGENT - one-time laptop remote-control permission' -ForegroundColor Cyan
Write-Host 'This changes only YOUR Windows user account. It does not enable a public network port.'
Write-Host 'If enabled, O-AGENT launches a VISIBLE Windows input companion when it starts.'
Write-Host 'The companion can only send input after your signed-in OWNER phone chooses Control'
Write-Host 'and a human-selected laptop screen is actively shared. A control lease lasts 20 minutes.'
Write-Host 'Close the visible companion window at any time, or select Stop control on mobile.'
Write-Host 'Do not leave O-AGENT running on an untrusted or shared computer.'
Write-Host ''
Write-Host ("Current setting: " + $(if ($active) { "ENABLED" } else { "DISABLED" }))
$choice = Read-Host 'Type ENABLE to trust this laptop, DISABLE to revoke, or press Enter to cancel'
if ($choice -cne 'ENABLE' -and $choice -cne 'DISABLE') {
    Write-Host 'No settings changed.'
    exit 0
}
$config | Add-Member -NotePropertyName 'RemoteControlTrusted' -NotePropertyValue ($choice -ceq 'ENABLE') -Force
Save-OAgentConfig $config
if ($choice -ceq 'DISABLE') {
    # Close only our own enrolled trusted helper, never unrelated PowerShell windows.
    try {
        $helperPath = Join-Path $PSScriptRoot 'remote-control.ps1'
        Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
            Where-Object {
                $_.CommandLine -and
                $_.CommandLine.IndexOf($helperPath, [StringComparison]::OrdinalIgnoreCase) -ge 0 -and
                $_.CommandLine.IndexOf('-Trusted', [StringComparison]::OrdinalIgnoreCase) -ge 0
            } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    } catch { Write-Host 'Close the existing O-AGENT remote-control helper window to revoke it.' -ForegroundColor Yellow }
    Write-Host 'One-tap Windows remote input DISABLED. The local helper was revoked.' -ForegroundColor Green
} else {
    Write-Host 'One-tap Windows remote input ENABLED for this trusted computer.' -ForegroundColor Green
    Write-Host 'Restart O-AGENT.cmd to launch its visible control companion automatically.'
    Write-Host 'Select a screen in the O-AGENT desktop sharing page once, then use Control on mobile.'
}
