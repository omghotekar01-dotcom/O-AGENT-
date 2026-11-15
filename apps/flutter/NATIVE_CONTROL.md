# Native O-AGENT mission control

The primary Android and iOS screen is Flutter-native, not a browser command center.
The earlier legacy operator-token project screens remain available inside the app.

Keycloak uses the OS system browser ONLY for OAuth PKCE sign-in and redirects
to com.omiiii.oagent:/oauth2redirect. Normal work and approvals use native APIs.
The dedicated oagent-mobile public client is registered by the Windows starter.
Refresh credentials are encrypted with OS secure storage; access tokens stay in memory.

Native Home, Work, Inbox, Devices and Activity call real signed-in SaaS endpoints.
Work creates supervised requests; Inbox requires a separate hash-bound decision.
Provider capabilities are shown only when enabled on the enrolled worker.

Unsupported arbitrary ChatGPT website takeover and screen streaming are not claimed.
The laptop worker must remain on and reachable through Tailscale.
Real Codex CLI session turns require a verified native provider session ID.

Physical acceptance requires a batched new APK, secure login, heartbeat,
read-only workspace inventory, exact approval, and genuine result verification.
No APK is generated on ordinary code commits.

## Consolidated native Android pilot build

- Flutter 0.13.0+15 restores a native-first mobile interface.
- Native PKCE login uses the registered `oagent-mobile` Keycloak public client.
- Home/Work/Inbox/Devices/More and run activity render in Flutter.
- Laptop enrollment, fingerprint approval and revocation are inside Flutter.
- The previous native operator-token workspace remains accessible separately.
- The Android debug APK must still be tested on a real phone after installation.
- Background native SaaS push notifications, arbitrary AI website takeover and
  unsupported live editor/tab synchronization are not represented as complete.
- The previous Android APK remains a separate older version and will still
  use its original browser handoff until replaced.

## Native saved Codex CLI and VS Code threads

Native Work shows genuine saved threads from the enrolled laptop's official
Codex app-server read-only thread/list, thread/read and thread/turns/list APIs.
The worker checks canonical folder boundaries and symlinks before publishing
a bounded latest-message snapshot via device-signed HTTPS to PostgreSQL
tenant-isolated tables (additive migrations 004 and 005).

- Open an existing saved thread and see available conversation text, last
  synchronization, enrolled project folder and device.
- Enter the next instruction inside that native conversation; inspect its
  exact prompt, folder and permissions before creating a supervised request.
- A separate confirmation in native Inbox is REQUIRED before the worker
  resumes a saved Codex thread. Individual tools also require permission.
- Native run history includes paginated events, pending cancellation and
  interrupted-run recovery WITHOUT automatic replay.
- Threads from another PC or outside the enrolled project are excluded.
- Native Devices reports CLI unavailable, no stored threads, RPC failure or
  timeout rather than claiming a connection that is not working.

A saved thread is NOT a live attachment to another IDE's running turn.
O-AGENT can safely continue supported saved sessions; it cannot seize
arbitrary existing ChatGPT browser tabs or inject into running terminal UIs.
Only bounded recent messages are shown. Image/file uploads, streaming screen
control, universal conversation takeover and background SaaS push remain
incomplete. The enrolled Windows laptop must remain on, online and signed in.

Windows quick-start enables read-only discovery by default in the enrolled
workspace. Set OAGENT_ENABLE_CODEX_DISCOVERY=0 to opt out. Supervised Codex
continuation appears after verified local discovery; set
OAGENT_ENABLE_CODEX_LOCAL_SYNC=0 for explicit execution opt-out. The user's
own Codex CLI provider authentication is required; no paid API key is created.

Only build a batched APK once backend and Flutter tests pass. Physical
acceptance on the owner's phone and actual Windows VS Code environment
is required; CI cannot establish full live IDE interoperability.

## Consolidated Android build 0.14.0+16

This release batch adds verified read-only discovery of locally persisted
Codex/VS Code sessions inside the enrolled project, native saved-thread
history and prompt composition, exact approval, native cancellation, run
recovery without replay, Windows/Linux path verification, and Codex-specific
connection diagnostics. It preserves the OAuth native login, private ports
and old native workspace. Nothing in this batch grants access to arbitrary
consumer ChatGPT website tabs or controls another IDE's already-running turn.

After installing the debug APK, check live Windows/Android integration:
1. Complete PKCE sign-in through Tailscale in the mobile app.
2. Confirm signed worker online and Codex scan status under Devices.
3. Open a real existing saved Codex thread under Work.
4. Send the next prompt from the conversation and review in Inbox.
5. Approve the exact request, then observe real run progress/results.
6. Test denial, offline state, stale snapshots, and no-replay recovery.

A green CI and a successful Android build do not replace this physical test.

## Native SDK conversations and hardening — Android 0.15.0+17

This is a single consolidated Android **debug pilot** release batch, not a
commercially signed or independently security-reviewed mobile release.

- Existing local Codex/VS Code threads are read via the official disposable
  app-server list/read/paginated-turns operations. Full histories are never
  loaded without bounds and the app never injects into active IDE windows.
- The owner can browse prior completed Claude Agent SDK and GitHub Copilot
  SDK sessions inside Work, inspect genuine prior prompts/results and request
  continuation with the same provider-owned ID and enrolled project path.
- An authenticated app cannot forge or guess a Codex/SDK session ID:
  the server verifies the device, provider and exact directory using tenant
  RLS and signed worker records. Codex snapshots must also be recent.
- Submitting a continuation only creates a pending approval. A separate
  explicit owner action in Inbox is necessary before worker execution.
- OAuth refresh is deduplicated across concurrent native API requests.
  Unchecked Remember phone never stores a rotated refresh key silently.
- Old private-pilot gateways lacking the SDK-session list endpoint return
  404 and the native app keeps its earlier worker, run and approval screens.
- The old legacy Flutter operator-token workspace remains accessible.

### Single owner acceptance procedure

1. Pull the private development branch in the SAME existing Windows folder.
2. Run START-O-AGENT.cmd; preserve HTTPS port 8443 -> localhost:8787 and
   the unrelated application on HTTPS 443 -> localhost:8000.
3. Keep CONNECT-O-AGENT-WORKER.cmd running on the authorized project.
4. Install the new debug APK. Check native Home, Work, Devices and Inbox.
5. Check saved Codex threads. If CLI unavailable, the device shows a
   specific read-only discovery diagnostic. Inspect one genuine history.
6. Start or resume a configured SDK provider session; then verify native
   history and send a follow-up prompt with an exact separate approval.
7. Verify denial, worker offline, invalid thread IDs, token rotation and
   interrupted-run recovery. Do not claim passed physical tests until run.

Still incomplete: arbitrary consumer ChatGPT.com session takeover, real
desktop screen/video mirroring, remote attachment to an already-running
third-party VS Code/Cursor process, image/document uploads in this new
SaaS control channel, push alerts when the native app is terminated,
provider OAuth account integration at commercial scale, billing, and
always-on hosted production infrastructure. A worker must remain online.
