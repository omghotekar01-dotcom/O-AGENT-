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
6. **Ordering and acknowledgments:** drag then click then paste,
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
