# O-AGENT v0.5 design & real cloud-agent integration (development candidate)

## Product goal

O-AGENT is a user-authorized multi-agent remote **supervision console**,
not an artificial chat interface pretending to control a laptop. It must
distinguish (a) a real account-owned agent session, (b) authenticated provider
status, (c) a controllable operation, (d) permission and risk, and (e) real
on-screen streaming. A badge is not a remote-control API.

## iOS-inspired Flutter design system

Original implementation in:
- apps/flutter/lib/ui/ios_components.dart
- apps/flutter/lib/ui/remote_mission_control.dart
- apps/flutter/lib/ui/cursor_cloud.dart
- apps/flutter/lib/theme.dart

Visual direction drawn from publicly available SwiftUI guidance:
- Clear large editorial titles, deep graphite text, paper-white grouped
  surfaces, slight borders/shadows, purple for controlled actions, mint for
  verified/online, amber for pending approvals, red for errors.
- System-native glyphs, SF-symbol-inspired icon metaphors, adaptive widths
  for compact phone and landscape/tablet, Dynamic Type/large text friendly
  line wrapping, semantic statuses, true onTap affordances.
- Cupertino segmented run filters, sheet-based credential entry, explicit
  action confirmations, accessible labels and clear back navigation.
- States are genuine (loading, empty, verified, not configured, stale,
  disconnected, running, waiting for approval, finished). **No fake live
  status or fake screenshots**.
- No paid font files, no assets copied from third-party mockups, and no
  bundled credentials. License compatibility must be reviewed before reusing
  any source rather than merely its conceptual patterns.

Design links reviewed:
- https://github.com/cjwirth/awesome-ios-ui — grouped reusable components,
  navigation, feedback and interaction catalogs; many older UIKit demos need
  modernization, so do not import the whole list.
- https://github.com/muhittincamdali/iOSAppTemplates — reusable SwiftUI
  templates and component boundaries, not literal screen reproduction.
- https://github.com/sameh-bakleh/ios-marketplace-product-app — typed HTTP
  layer, loading/error/empty states, Keychain and test boundaries.
- https://github.com/Pankajrana01/SuperWallet-SwiftUI — glanceable dashboard
  hierarchy and clear activity rows.
- https://github.com/ios-lib/AppDesignKit — restrained Swift-based layout
  ideas; its UIKit screens have no production backend.
- https://github.com/wshobson/agents/blob/main/plugins/ui-design/skills/mobile-ios-design/SKILL.md — Apple HIG clarity, deference, depth, dynamic type and accessibility.
- https://github.com/topics/ios-app
- https://github.com/topics/ios-ui
- https://github.com/topics/ios-style?o=asc&s=stars
- https://github.com/topics/uiux?l=swift
- https://60fps.design/apps/github — motion inspiration, paid gallery not
  source assets.
- https://medium.com/@lisadziuba/33-awesome-github-lists-for-ios-development-336691520d0f — discovery links, not a design specification.

## Cursor Cloud Agents v1 — implemented adapter and mobile workflow

**Cloud Agents are distinct from an independently open local Cursor IDE tab.**
The official Cursor Cloud Agents API (https://prod.cursor.com/docs/cloud-agent/api/endpoints)
supports listing agents, reading runs, sending new runs, steering active
agents, cancelling, and retrieving final output. It may require a plan with
Cloud Agent access and may incur provider charges. No "free universal model"
can replace its authentication or user permissions.

New server module apps/control-plane/src/cursor-cloud.mjs uses the fixed
official API origin at https://api.cursor.com. Each account can connect its
**own** API key via its signed-in HTTPS mobile session. O-AGENT encrypts it
with the AES-GCM vault and only sends it server-side to Cursor; it never
returns keys to app responses. Confirmed status requires successful
authenticated GET /v1/me.

User/account endpoints:
- GET/PUT/DELETE /api/account/cursor — connection state and encrypted key.
- POST /api/account/cursor/verify — real provider identity.
- GET /api/account/cursor/agents — provider-owned sessions.
- GET /api/account/cursor/agents/:id — agent metadata.
- GET /api/account/cursor/agents/:id/runs — real runs.
- GET /api/account/cursor/agents/:id/runs/:runId — terminal output.
- POST /api/account/cursor/agents/:id/runs — explicit prompt or "steer".
- POST /api/account/cursor/agents/:id/runs/:runId/cancel — terminal cancellation.

Every request is scoped to the account's own credential and checked for a
fixed host and strict path/ID validation. Backend writes require a unique
request ID and store a bounded idempotency result. Unknown outcome after a
network failure is flagged as uncertain; **do not automatically resend**
as it might create duplicate billable runs. Cloud Agents API v1 does not
expose the same device-level tool approval mechanism as the Codex app-server;
the phone explicitly asks before sending/cancelling a run, and it never
invents per-tool consent callbacks.

### Using Cursor Cloud

1. Deploy/start O-AGENT with a protected backend vault key configured.
2. Open **Remote → Cursor Cloud Agents** as workspace owner, or
   **My AI workspace → Connections → Cursor Cloud** as an invited user.
3. In Cursor Dashboard → API Keys create your own user/authorized service
   key. Paste it into the mobile masked credential sheet.
4. Tap Save and verify. Inspect the returned identity.
5. Create or find an agent in Cursor Cloud (the provider, not a local IDE tab).
6. Open the agent, inspect its real runs and final output.
7. Enter prompt, optionally select "Steer current run", review exact agent and
   prompt plus billing warning, and confirm. Inspect progress and final result.
8. Cancel an ongoing run only after separate confirmation. If the result is
   unclear due to a network failure, refresh the provider's real run list.
9. Disconnect to delete that account's O-AGENT encrypted key. Disconnecting
   does not delete the original cloud agent in Cursor.

**Device/production acceptance still required:** a real Cursor API-enabled
account and end-to-end web/mobile approval test. CI tests use a strict
protocol mock; they are not evidence that the owner's account is provisioned.

## Remaining platform boundaries (not to be marked "complete")

- Claude Code Agent SDK and GitHub Copilot SDK still need signed local/
  hosted runtimes, explicit SDK session ownership, permission hooks and
  per-user authentication.
- VS Code requires a user-installed, consented editor extension or local
  desktop companion. Cursor Cloud does not attach to Cursor IDE windows.
- Existing ChatGPT/Claude/Gemini web chats, especially managed Work browser
  sessions, do not have a verified general external takeover API.
- Live computer/browser frames and input must require a consented Windows
  capture companion with visible indicator and revocable view/control tokens.
- Background phone notifications require provider-specific push credentials
  and APNs/FCM setup; foreground SSE is not a substitute.
- Always-on cloud control **requires** an actually provisioned HTTPS backend,
  independent cloud workers and durable state. The single-instance Render
  blueprint is not a provisioned hosted service or a promise the laptop will
  continue running after power off.

## Acceptance and build quota

Backend: node --test tests/*.test.mjs, full API auth/isolation, fixed Cursor
API origin, invalid/unsupported paths, per-user key secrecy, idempotency.
Flutter: flutter analyze, flutter test including credential sheet teardown,
small screens and offline/empty/provider-error status.
Windows: launcher and worker regression checks.
Physical device: authenticated real Cursor Cloud account, real Codex CLI
account, real prompt, remote approval/deny, reconnect and offline cases.

**Native APK packaging only after these changes form one approved milestone.**
Do not rebuild Android for ordinary code commits; guard with the existing
mobile-release trigger.
