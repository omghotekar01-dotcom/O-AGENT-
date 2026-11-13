[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\common.ps1"

# This process MUST remain visible in the interactive Windows login session.
# It is never auto-started by O-AGENT.cmd, does not create a network listener,
# and stops accepting input when its terminal closes or the short lease expires.
$config = Read-OAgentConfig
$workerId = [string]$config.WorkerId
$secret = Unlock-OAgentSecret $config.WorkerTokenEncrypted
# Follow the actual port saved by O-AGENT.cmd, even when this companion
# is launched in a NEW Explorer/PowerShell process without OAGENT_PORT.
$port = 8787
$running = Get-OAgentPidState
if ($running -and ($running.PSObject.Properties.Name -contains 'Port') -and $running.Port) {
    $port = [int]$running.Port
}
if ($env:OAGENT_PORT) { $port = [int]$env:OAGENT_PORT }
if ($port -lt 1024 -or $port -gt 65535) { throw 'Invalid O-AGENT backend port.' }
$origin = "http://127.0.0.1:$port"
$headers = @{ Authorization = "Bearer $secret" }
$secret = $null

function Get-OAgentInputError([System.Management.Automation.ErrorRecord]$failure) {
    # Prefer the backend's sanitized JSON error over PS 5.1's generic
    # "remote server returned an error" status. Never print token/headers.
    $details = $failure.ErrorDetails.Message
    if (-not $details -and $failure.Exception.Response) {
        try {
            $stream = $failure.Exception.Response.GetResponseStream()
            if ($stream) {
                $reader = New-Object System.IO.StreamReader($stream)
                try { $details = $reader.ReadToEnd() }
                finally { $reader.Dispose() }
            }
        } catch { }
    }
    if ($details) {
        try {
            $json = $details | ConvertFrom-Json
            if ($json -and ($json.PSObject.Properties.Name -contains 'error') -and $json.error) {
                return ([string]$json.error).Substring(0, [Math]::Min(400, ([string]$json.error).Length))
            }
        } catch { }
    }
    $web = $failure.Exception
    if ($web -is [System.Net.WebException] -and -not $web.Response) {
        return "Local backend not reachable at $origin. Start O-AGENT.cmd first."
    }
    return 'Local backend request failed; check the backend and sharing status.'
}

function Assert-OAgentBackendReady {
    try { $health = Invoke-RestMethod -Uri "$origin/health" -Method Get -TimeoutSec 3 }
    catch {
        throw "O-AGENT backend is OFFLINE at $origin. Double-click O-AGENT.cmd and confirm ONLINE, then retry REMOTE-CONTROL.cmd. This is a local Windows connection; Tailscale is not required here."
    }
    if ($health.status -ne 'ok' -or $health.service -ne 'oagent-control-plane') {
        throw "Port $port is not running the expected O-AGENT backend. Stop the conflicting service and restart O-AGENT.cmd."
    }
}


Write-Host ''
Write-Host 'O-AGENT — opt-in Windows remote pointer and keyboard' -ForegroundColor Cyan
Write-Host 'WARNING: This lets your paired OWNER phone click and type into your'
Write-Host 'currently focused Windows applications for up to 20 minutes.'
Write-Host 'Only enable on your own trusted computer, while sharing your screen.'
Write-Host 'Never type passwords, payment details or private tokens using remote input.'
Write-Host 'Elevated apps, Windows sign-in and secure desktop cannot be controlled.'
Write-Host 'Leave this window visibly open. Close it or press Ctrl+C to stop.'
Write-Host ''
$confirmation = Read-Host 'Type ENABLE to opt in (anything else cancels)'
if ($confirmation -cne 'ENABLE') { Write-Host 'No remote control enabled.'; exit 0 }

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class OAgentUserInput {
  [StructLayout(LayoutKind.Sequential)]
  private struct Point { public int X; public int Y; }
  [DllImport("user32.dll")] private static extern bool GetCursorPos(out Point p);
  [DllImport("user32.dll")] private static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] private static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
  [DllImport("user32.dll")] private static extern void keybd_event(byte key, byte scan, uint flags, UIntPtr extra);
  [StructLayout(LayoutKind.Sequential)] private struct Input {
    public uint type; public InputUnion data;
  }
  [StructLayout(LayoutKind.Sequential)] private struct MouseInput {
    public int dx; public int dy; public uint mouseData;
    public uint flags; public uint time; public IntPtr extra;
  }
  [StructLayout(LayoutKind.Explicit)] private struct InputUnion {
    [FieldOffset(0)] public KeyInput keyboard;
    [FieldOffset(0)] public MouseInput mouse;
  }
  [StructLayout(LayoutKind.Sequential)] private struct KeyInput {
    public ushort vk; public ushort scan; public uint flags; public uint time; public IntPtr extra;
  }
  [DllImport("user32.dll", SetLastError=true)]
  private static extern uint SendInput(uint count, Input[] inputs, int size);
  public static int InputStructSize() { return Marshal.SizeOf(typeof(Input)); }
  public static void Move(int dx, int dy) {
    Point p; if (GetCursorPos(out p)) SetCursorPos(p.X + dx, p.Y + dy);
  }
  public static void Click(string kind) {
    uint down = kind == "right" ? 8u : 2u;
    uint up = kind == "right" ? 16u : 4u;
    mouse_event(down, 0, 0, 0, UIntPtr.Zero);
    mouse_event(up, 0, 0, 0, UIntPtr.Zero);
    if (kind == "double") {
      System.Threading.Thread.Sleep(65);
      mouse_event(down, 0, 0, 0, UIntPtr.Zero);
      mouse_event(up, 0, 0, 0, UIntPtr.Zero);
    }
  }
  public static void Scroll(int steps) {
    mouse_event(0x0800u, 0, 0, unchecked((uint)(steps * 120)), UIntPtr.Zero);
  }
  public static void Key(string name) {
    byte key = 0;
    switch (name) {
      case "enter": key = 0x0D; break;
      case "escape": key = 0x1B; break;
      case "backspace": key = 0x08; break;
      case "tab": key = 0x09; break;
      case "left": key = 0x25; break;
      case "up": key = 0x26; break;
      case "right": key = 0x27; break;
      case "down": key = 0x28; break;
      default: return;
    }
    keybd_event(key, 0, 0, UIntPtr.Zero);
    keybd_event(key, 0, 2, UIntPtr.Zero);
  }
  public static void TypeText(string value) {
    foreach (char ch in value) {
      Input[] events = new Input[2];
      events[0].type = 1;
      events[0].data.keyboard.scan = (ushort)ch;
      events[0].data.keyboard.flags = 0x0004u;
      events[1].type = 1;
      events[1].data.keyboard.scan = (ushort)ch;
      events[1].data.keyboard.flags = 0x0004u | 0x0002u;
      if (SendInput(2, events, Marshal.SizeOf(typeof(Input))) != 2)
        throw new InvalidOperationException("Windows rejected keyboard input. Check the active desktop.");
    }
  }
}
'@ -ErrorAction Stop

function Send-OAgentInputRequest([string]$action, [hashtable]$data) {
    $data['workerId'] = $workerId
    try {
        return Invoke-RestMethod -Method Post -Uri "$origin/api/workers/remote-input/$action" -Headers $headers -ContentType 'application/json' -Body ($data | ConvertTo-Json -Compress) -TimeoutSec 6
    } catch {
        throw (Get-OAgentInputError $_)
    }
}

$armed = $false
try {
    Assert-OAgentBackendReady
    $pair = Send-OAgentInputRequest 'prepare' @{}
    $armed = $true
    Write-Host ''
    Write-Host "Pairing code: $($pair.pairingCode)" -ForegroundColor Yellow
    Write-Host 'On your phone: Remote > See my laptop > Full screen > Pair Windows control.'
    Write-Host 'Code expires after 2 minutes; once paired, remote control lasts 20 minutes.'
    Write-Host 'Stop sharing your screen or close this window to revoke control.'
    Write-Host ''
    while ($true) {
        try {
            $next = Send-OAgentInputRequest 'next' @{}
        } catch {
            Write-Host "Remote input stopped: $($_.Exception.Message)" -ForegroundColor Yellow
            break
        }
        $a = $next.action
        if ($null -ne $a) {
            try {
                switch ([string]$a.type) {
                    'move' { [OAgentUserInput]::Move([int]$a.dx, [int]$a.dy) }
                    'click' { [OAgentUserInput]::Click([string]$a.button) }
                    'scroll' { [OAgentUserInput]::Scroll([int]$a.steps) }
                    'key' { [OAgentUserInput]::Key([string]$a.key) }
                    'text' { [OAgentUserInput]::TypeText([string]$a.text) }
                }
            } catch {
                Write-Host 'Windows did not accept an input action; check focus and permissions.' -ForegroundColor Yellow
            }
        }
        Start-Sleep -Milliseconds 190
    }
} catch {
    Write-Host "Could not enable remote input: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Required: O-AGENT backend ONLINE at $origin; selected screen sharing active; same enrolled worker token." -ForegroundColor Yellow
    Write-Host 'Screen preview must say Receiving images before you start this helper.' -ForegroundColor Yellow
    exit 1
} finally {
    if ($armed) {
        try { $null = Send-OAgentInputRequest 'stop' @{} } catch {}
    }
}
