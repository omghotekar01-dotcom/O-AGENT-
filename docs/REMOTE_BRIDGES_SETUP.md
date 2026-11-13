# O-AGENT — consolidated remote-control development release

This guide describes the code in PR #19, **not a verified production deployment**.
O-AGENT manages explicitly enrolled, user-authorized agent sessions.
It does not take over an independently open ChatGPT/Claude/Copilot browser tab
or arbitrary Cursor and VS Code editor sessions.

## 1. Private laptop-backed setup via Tailscale

1. Update the local O-AGENT backend and Windows worker from the matched release.
   Existing operator and worker secrets must be kept and backed up.
2. Keep your Tailscale Serve **HTTPS** origin (for example the private
   tailnet host you already use). Android requires a valid trusted certificate.
3. Connect the mobile application using **My owner workspace** and its own
   backend URL / operator token fields. Do not paste tokens into source code.
4. Set the laptop worker's OAGENT_WORKSPACE_ROOT to the trusted parent folder
   containing the coding projects you intend to supervise.
5. For Claude Agent SDK, install the separately pinned package
   @anthropic-ai/claude-agent-sdk@0.3.322 on the worker and authenticate
   its supported CLI/SDK identity. Opt in with
   OAGENT_ENABLE_CLAUDE_AGENT_SDK=1.
6. For GitHub Copilot SDK, install @github/copilot-sdk@1.0.30 and sign in
   using the Copilot SDK/CLI's supported account flow, then enable
   OAGENT_ENABLE_COPILOT_SDK=1. Actual Copilot access is subject to its
   subscription and organization policies.
7. Restart the worker. Remote → **Claude Agent SDK & GitHub Copilot** displays
   enrolled online workers only. Select an existing workspace folder, choose
   Read-only or Project edits, and review the exact prompt. There is a
   second owner approval before the turn executes. For eligible edits, every
   tool action is routed to a separate expiring approval in the phone UI.
   Unknown tools, browser/MCP, outside-workspace paths and unsafe symlinks
   fail closed. Shell is disabled by default; enabling
   OAGENT_ALLOW_SHELL_TOOLS=1 can execute arbitrary OS commands and should
   only be used in a locked-down container with explicit per-command approval.
   A command approval is not an OS sandbox.

## 2. VS Code companion installation

1. Build/package apps/vscode as a VS Code extension, then install it manually
   into the VS Code instance you consent to share. This is source code, not
   yet a published, signed VS Code Marketplace package.
2. Open a trusted workspace. Choose **O-AGENT: Configure Secure Companion**,
   supplying the private HTTPS backend and the *worker* token (not the
   operator token). The extension stores them in VS Code SecretStorage.
3. Choose **O-AGENT: Start Remote Workspace Companion** and approve its local
   enrollment dialog. The status bar reports the actual state.
4. On the owner phone, open Remote → VS Code companion. Select an enrolled
   editor and request a path relative to its workspace, e.g. src/main.ts.
5. The owner must approve the exact file-open request on the phone. Then
   the person at VS Code must approve a second local modal. No file contents
   are transmitted to the mobile UI; this extension does not edit, execute
   terminals or read VS Code/Copilot chat conversations.
6. Choose **O-AGENT: Stop Remote Workspace Companion** to revoke its polling.

## 3. Live view-only selected screen / window

1. On the owner phone, open Remote → **View consented laptop preview** and
   copy the screen-sharing URL.
2. Open the URL on the laptop in a modern browser **inside the same private
   HTTPS backend** and enter the owner token. The token remains in page memory.
3. Press **Choose a screen or window**. The browser must display its native
   screen picker and visible sharing indicator. Choose only material you own.
4. The browser sends limited JPEG preview frames. The backend stores only the
   latest frame **in RAM**, expires it after a few seconds, limits request size
   and frame rate, and revokes the capture session after at most 30 minutes.
5. Open the phone preview to view the selected content. Stop using either
   the browser's sharing controls or **Stop immediately** on mobile.

This is NOT interactive remote desktop, hidden screen recording, unattended
streaming or remote mouse/keyboard input. It works only while the laptop and
consented sharing page stay open. The API token is never encoded into the URL.

## 4. Background approval notifications (FCM)

1. Create a Firebase project you control and register the Android app ID
   and (for iOS) the Apple bundle ID. Configure the Android/iOS Firebase
   application identifiers at native build time.
2. Create a Firebase service account authorized to send FCM HTTP v1 push,
   store the JSON privately, encode it as base64 and set
   OAGENT_FCM_SERVICE_ACCOUNT_BASE64 **only on the backend**.
3. For iOS, configure APNs authentication keys, the Push Notifications
   entitlement, provisioning/signing and the remote notification capability.
4. Build one Android/iOS artifact using its app-specific Firebase
   configuration. Never put the service account private key into Flutter,
   GitHub source code or the distributed APK.
5. Each signed-in user opens Notifications and presses
   **Enable on this device** to approve OS notification permission and
   register their own FCM token (encrypted by the O-AGENT backend vault).
6. Use the same screen to list or revoke registered devices. Provider output,
   prompts, file paths, keys and tool arguments are intentionally not included
   in notifications. Approval decisions are made only after opening the
   authenticated O-AGENT app and reviewing exact requests.
7. Test by creating a real write-capable agent action, moving the app to the
   background, receiving the push and approving/denying from the authenticated
   UI. Verify permission expiry, revoked device tokens and an offline device.

Without real Firebase/APNs provisioning and a physical device this remains
an implemented and mock-tested integration, NOT verified background delivery.

## 5. Independent HTTPS backend and optional cloud worker

1. Provision your own Linux VPS with a routable DNS domain and ports 80/443.
   Install a current Docker Engine + Compose plugin.
2. Copy deploy/cloud.env.example to **.env.cloud** and set distinct random
   OAGENT_API_TOKEN / OAGENT_WORKER_TOKEN, one durable 32-byte
   OAGENT_VAULT_KEY_BASE64, domain and public HTTPS origin. Put private
   environment files outside version control and protect permissions.
3. Copy deploy/worker.env.example to **.env.worker**. Include *only* the
   matching worker token and desired SDK toggles. Never inject the owner
   token, vault key, FCM admin key or mail secret into the worker container.
4. Run:
   docker compose --env-file .env.cloud -f docker-compose.cloud.yml up -d --build
   The single-instance backend uses a persistent named Docker volume and the
   Caddy reverse proxy obtains HTTPS certificates.
5. Once an SDK identity and its repositories have been installed in the
   isolated worker container, run:
   docker compose --env-file .env.cloud -f docker-compose.cloud.yml --profile worker up -d --build
6. Check /health over HTTPS and use the mobile app's owner connection screen.
   Provision email sender/verification separately before enabling public
   registration. Test encrypted keys and access revocation before inviting
   anyone outside your trusted tailnet.

This is **self-hostable infrastructure code**, not a live hosted deployment.
It has no guarantee of high availability: one process and a JSON state file
must not be scaled to multiple concurrent instances. Provider SDK workers
run independently of your laptop only once a real cloud worker has been
provisioned, authenticated and connected.

## 6. Release acceptance gates

- Source: npm run check, npm test (including authenticated account isolation,
  permission expiry, path traversal, screen lease and FCM protocol mocks).
- Flutter: flutter analyze --no-pub and flutter test --no-pub on compact and
  standard screen widths.
- Native: one consolidated debug APK (and unsigned iOS simulator build if
  required), verified on the user’s actual phone.
- Security: no embedded secrets, cross-account access, stale screen frames,
  unapproved SDK tool calls, or bypass of native editor consent.
- Provider: real Claude and Copilot SDK login, actual agent turn, exact per-tool
  approval/deny, offline reconnect and billing/organization policy checks.
- Infrastructure: DNS/HTTPS, persistent storage, backup restore, Firebase
  service account, APNs, and cloud worker provisioning on an owner-controlled
  host. Verify no admin keys leak into the worker container.

Only the stages actually tested may be marked passed. Website-chat takeover,
unrestricted desktop input, multi-tenant cloud workers and high-availability
SaaS are **not implemented** by this candidate.
