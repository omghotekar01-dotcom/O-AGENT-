# O-AGENT responsive remote screen/input — acceptance plan

Release candidate: mobile 0.10 preview, Windows helper & backend revision in the
same repository checkout. **Not** an unattended computer-control feature.

## Verified implementation changes

- Browser capture continues to require the physical laptop user's
  `getDisplayMedia` picker. It now requests up to 8 FPS from the browser and
  adaptively publishes up to ~4 JPEG previews per second, subject to network
  throughput, browser background throttling and load.
- Frame uploads are bounded (240 KB server max). New phone clients request
  `GET /api/screen/frame?after=<sequence>`; HTTP 204 means nothing changed.
  Frame content remains ephemeral in backend memory.
- The fullscreen phone viewer polls only when visible, keeps the previously
  decoded image on 204, and refreshes input/screen status separately.
- Windows keyboard and mouse require owner authentication, visible helper,
  fresh consented capture, short-lived 8-digit pairing and a 20-minute
  session. Pairing, capture and input can each be stopped independently.
- Windows local input helper polls every 70 ms. Adjacent trackpad movement
  deltas coalesce on the backend without moving clicks or keystrokes past each
  other. Touch gestures accumulate fractional movements, and the phone queues
  discrete actions rather than silently dropping a click during movement.
- The Windows helper acknowledges its previous action (success/failure)
  during the next poll, without an additional HTTP request or logging the
  text typed. Owner UI distinguishes backend queue acceptance from Windows
  input execution. It still cannot prove each target app processed input.
- The owner-only website now has Live desktop, including incremental JPEG
  preview, a paired virtual touchpad, allowlisted keyboard actions, and
  immediate stop controls. Leaving this page or signing out discards pending
  browser input. Authenticated blob images are revoked when replaced.
- Keyboard supports text, arrows, Escape, Enter, Tab, Backspace, and a small
  audited shortcut list (Copy/Paste/Cut/Undo/Redo/Select all/Save/Find).
  There is no arbitrary hotkey/script execution, clipboard exfiltration,
  Windows secure-desktop control or unattended input.
- O-AGENT's Remote screen displays an actual captured-frame rate and input
  queue depth; these are measurements, not guaranteed frame rates.

## Manual acceptance matrix — required on physical devices

Do not mark these as passed until a person observes the results on the
real laptop and phone. Record device OS/version, app revision, backend origin,
Wi-Fi/cellular conditions, timestamps and any error descriptions.

1. **Start/stop:** laptop O-AGENT online; browser screen consent; phone sees
   fresh frame; stopping browser or tapping Stop immediately removes preview.
2. **Display consistency:** switch among browser/VS Code windows; selected
   window must be the only capture source. Background tab throttle is
   permitted, but must show stale status rather than pretending to be live.
3. **Performance:** measure at least 30 seconds on local Wi-Fi and on mobile
   Tailscale data. Record approximate time from moving a window to the
   corresponding phone frame, actual estimated FPS, and connection loss rate.
   There is no universal zero-latency target.
4. **Trackpad:** after visible Windows helper pairing, slow and fast drags
   move the real pointer in the correct direction; speed slider works.
   Tap clicks **current pointer position**, not arbitrary pixels on the image.
   Long press/right click/double click and scrolling work.
5. **Keyboard:** enter test-only text into Notepad, test Backspace, Tab,
   arrows, Ctrl+A, Copy/Paste, Undo and Save in a harmless file. Never use
   credentials, personal data, payments or real tokens during testing.
6. **Phone image paste:** choose a harmless PNG/JPEG under 1.5 MB,
   focus a known ChatGPT/VS Code test composer, explicitly confirm Paste
   image on the phone, then verify that it appears on the laptop. Test image
   rejection, network interruption, 20-minute control expiry, clipboard
   cleanup, and a clipboard changed by the laptop user during paste.
7. **Ordering and acknowledgments:** drag then click then paste,
   20 consecutive times. No clicks, keys or paste requests should be
   lost or reordered. Confirm the input action receipt moves from queued
   to Windows-executed, or shows a clear rejected result. Repeat in web
   desktop touchpad as well as Android.
7. **Access isolation:** wrong owner token, missing helper, expired pair code,
   stopped capture, offline helper, expired 20-minute window and member
   account must all fail to control the desktop.
8. **Unsupported contexts:** UAC/lock screen, elevated apps, multiple
   monitor placement and selected application window vs full display.
   Remote image tapping is **not** pixel-accurate absolute cursor targeting.
9. **Recovery:** toggle airplane mode, temporarily stop worker/backend,
   rotate phone, background/foreground app, then stop and re-pair. UI should
   explain stale or disconnected state and recover without duplicate input.

## Provider sessions / AI agent scope

The Remote screen shows real Codex CLI and approved SDK task updates and
permissions generated under O-AGENT control. OpenAI/Anthropic/Gemini API
conversations are visible in the account workspace. These are **not**
equivalent to existing ChatGPT web projects, private Copilot Chat tabs,
claude.ai, Grok or other consumer-site conversations. A separate authorized
adapter is needed for each external provider/session type.

## Commercial launch blockers

The existing `docs/PRODUCT_RELEASE_GATES.md` remains authoritative:
per-tenant device identity and authorization, a real hosted backend, signing
keys, signed store release, privacy/terms and real-device QA are still needed.
The CI-generated debug APK must never be labeled a signed market release.


## One-time trusted mobile control (private preview)

1. On your own trusted Windows laptop, run
   `ENABLE-ONE-TAP-CONTROL.cmd` **once**, read the local warnings, and type
   `ENABLE`. Choosing `DISABLE` later revokes the setting and stops the
   locally enrolled visible helper. New installations may opt in during setup.
2. Restart `O-AGENT.cmd` once. Its Windows helper starts visibly and waits
   for owner activation; **no code is generated or requested on each session**.
3. On the **laptop**, open the authenticated O-AGENT dashboard → Live desktop,
   choose **Share this computer's screen** and select the exact display or
   window through Chrome/Edge's native picker. The screen cannot be silently
   captured by the phone; browser consent is a real platform limitation.
4. On the owner phone, open Remote → **Control laptop screen** (fullscreen).
   Press **Control**. A live picture and active visible helper are required;
   owner authentication is checked at the backend. After enabling, use touch
   to point/click, keyboard to type or **Send prompt** to type the exact text
   and press Enter in the currently focused application.
5. Press **Stop input** from the phone for view-only mode, or stop screen
   sharing/end the Windows helper to revoke local capabilities. Owner
   control expires after 20 minutes even if the phone stays open.
6. Temporary eight-digit pairing remains available only under the
   advanced/legacy setup path, not the default owner flow.

**Why a one-time laptop setup remains mandatory:** The app must not
grant arbitrary Windows mouse/keyboard permissions solely because a remote
user knows an API token. A visible, revocable local enrollment plus a
browser-selected capture and authenticated phone activation are the
private-preview consent boundaries. This is not yet device-attested,
per-user multi-tenant commercial authentication.

**Where screen taps work:** A shared **full display** on a Windows computer
with **one monitor** supports normalized tap-to-click (the Windows helper
independently checks the monitor count). Multi-monitor or tab/window share
uses the relative drag/click trackpad because screen-window coordinates
cannot be safely inferred from the picture. Windows secure desktop, UAC
and elevated app controls are excluded.

**HTTP 429:** Both the standalone browser capture page and embedded web
dashboard now back off and retry throttled frame uploads without destroying
the browser's ongoing screen permission. If the live frame becomes stale,
remote input pauses; network improvements are not a bypass of consent.

**ChatGPT and other AI apps:** The phone can interact with their *visible
laptop UI* through the explicitly shared desktop and human-driven input.
O-AGENT does not automatically retrieve existing private ChatGPT/Grok/
Claude/Copilot consumer chat histories or internal approvals unless
authorized provider APIs and adapters support them. Phone-selected PNG/JPEG images up to 1.5 MB can now be pasted into
the focused, visible Windows app using an owner-authenticated, ephemeral
transfer and the locally enrolled helper. Windows places the image briefly
on its clipboard, invokes Paste, then clears it if unchanged. This
does not guarantee every provider website accepts image paste, nor does
it submit the image automatically. PDF/docx upload to third-party sites is
not part of this functionality; test the image paste on real Chrome/Edge
and VS Code before claiming compatibility.
