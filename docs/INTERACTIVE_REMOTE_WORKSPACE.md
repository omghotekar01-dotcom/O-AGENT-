# O-AGENT — Real interactive remote workspace (candidate, not released)

This milestone addresses the owner's request for fullscreen mobile viewing,
a real (Windows-only) virtual trackpad, and live VS Code change indicators.
It remains opt-in, individually paired and strictly bounded.

## Reality check

- **Codex**: App-server session resume and turn/start are working based on
  the live phone events. The actual failed turn hit the Codex account's usage
  limit, reported by the provider as resetting November 21, 2026, 9:35 PM.
  O-AGENT cannot bypass it. After limit reset, retest in a scratch project.
- **ChatGPT Projects / Work**: Not an API-controlled session bridge. A bookmark
  is only a link. To interact with the visible ChatGPT UI, the owner can use
  the separately consented manual desktop control; this does not provide
  automatic synchronization, full chat access or agent permission callbacks.
- **Claude Agent SDK / GitHub Copilot SDK**: O-AGENT has enrolled provider-turn
  adapters, but each needs its own installed/authenticated SDK runtime and
  verification, subject to account and usage policy. No fake live sessions.
- **VS Code**: An optional local extension sends changed/unsaved *file names*
  and statuses, not file bodies or Git diffs. Remote file open remains
  approval-gated, including a second local editor confirmation.
- **Grok and other consumer AI sites**: Website links are not provider runtime
  connections. Integration needs an official API and its supported billing,
  authentication and access terms.

## Fullscreen view and Windows input (experimental)

1. Run the updated O-AGENT backend/worker on Windows and connect with your
   private owner phone. Use authenticated private HTTPS (e.g. Tailscale Serve).
2. In the owner mobile app open **Remote → See my laptop**.
3. On Windows, open the screen-sharing URL shown in that phone screen,
   enter your owner token on the trusted site, and select an exact window
   or screen in the browser picker. The browser indicator stays visible.
4. Phone: tap **Full screen / trackpad**. Before pairing, the screenshot
   can be enlarged/panned in fullscreen; input is disabled.
5. On the laptop, deliberately double-click **REMOTE-CONTROL.cmd**.
   A visible PowerShell window describes the risks. Type `ENABLE`.
   The helper prints an **8-digit code valid for 2 minutes**.
6. Phone fullscreen: tap **Pair control**, enter that code. Tap **Control**.
   Drag to move Windows' real pointer; tap to left-click, long-press to
   right-click and double-tap to double-click. Bottom controls scroll,
   send simple keys or type up to 300 characters to the focused app.
7. Tap **View** to return to pinch-zoom viewing. Tap **Stop control**, close
   the visible PowerShell helper, or stop the laptop screen share to revoke.
   The paired input lease expires after **20 minutes**. Input is not saved
   in O-AGENT's persistent task history.

**Restrictions:** Windows interactive desktop only. This is not unattended
hidden access, microphone/audio streaming, Windows login/secure-desktop
control, elevation, password-manager bypass, multi-device control or
autonomous AI clicking. The screenshot feed remains a low-bandwidth JPEG
preview; it is not a high-fidelity, zero-latency RDP/streaming solution.
The physical user can stop sharing and terminate the helper at any moment.
Never type secrets through this experimental channel. Remote input has no
effect if the computer is asleep/offline.

## VS Code live changed-file list

1. Install the O-AGENT VS Code companion extension from a trusted VSIX build
   using the method in `apps/vscode/README.md`.
2. Open a trusted project and run **O-AGENT: Configure Secure Companion**.
   Supply only your existing private HTTPS backend and enrolled worker token.
3. Run **O-AGENT: Start Remote Workspace Companion**, then explicitly accept
   the enrollment prompt. File *names and statuses* from Git plus VS Code
   dirty documents are sent every five seconds to an in-memory cache.
4. On the owner phone, open **Remote → Connect more AI tools (optional) →
   VS Code companion**, then inspect **Live workspace changes**.
5. Stop the companion to revoke. Snapshots expire from backend memory after
   20 seconds even if the editor or laptop disconnects.

**Not supported in this milestone:** arbitrary local file browsing, full diff
contents, live Copilot Chat transcripts, approvals raised inside independent
consumer apps, autonomous desktop vision/clicking, or complete browser/project
takeover.

## Security & release gate

- Both phone owner authorization and local Windows helper pairing are required.
- A fresh, visible, chosen browser screen-share must exist before input.
- No input queue, keystroke or VS Code file text is written to disk by
  these endpoints. Screen frames and editor metadata expire in memory.
- Input queue is bounded and rate-limited; only a small allowlist of event
  types/keys is supported. No arbitrary remote shell endpoint.
- The worker token currently has broad development-worker privileges and
  is not a production identity boundary. This must be replaced with
  device-scoped, expiring credentials before untrusted/public deployment.
- Test on real Windows and Android including incorrect code, stop, timeout,
  disconnected helper, stale screen, Windows DPI/multi-monitor behavior and
  secure desktop/UIPI isolation before release.
- Check Node tests, Flutter analyze/tests, VS Code syntax tests, and Windows
  PowerShell 5.1 script compilation. Do not trigger repeated APK builds for
  intermediate fixes.
