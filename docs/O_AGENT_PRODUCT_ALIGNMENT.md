# O-AGENT — agent-first cross-platform product contract
Updated: 2026-11-15

## Purpose (non-negotiable)

O-AGENT is an **iOS and Android remote control center for AI work already
owned and authorized by its user**. The default screen must show actual AI
agents, account/workspace connections, supported session histories, pending
permission requests, and truthful execution state. A generic "submit task"
dashboard, blind approvals, and a webview masquerading as a native app are
not an acceptable substitute.

### User's primary journey

1. Open the **same native Flutter app** on iPhone or Android.
2. Start in **Agents**, with ChatGPT, Codex CLI/IDE, Claude Agent SDK,
   GitHub Copilot SDK, VS Code workspaces, GitHub repos/Actions, Cursor Cloud,
   and relevant consumer AI services visible.
3. Open an agent to see **real authenticated sessions or a clearly
   explained connection limitation**. Never invent a session or infer
   "connected" from an installed app or from a worker capability alone.
4. Select a real, verified and eligible existing session, view its output
   and project, submit an exact follow-up message or supported attachment.
5. See actual progress/events, exact tool arguments, required permission
   approvals and resulting files/artifacts inside the app.
6. Leave the phone; authorized work continues on the available PC/cloud
   worker. Return to truthful statuses, notifications and replayed events.
7. Account connection, project choice and policy must be manageable through
   safe in-app forms. The normal PC startup is one double-click.

### Cross-platform UI/UX rules

- **One Flutter source** targeting iOS **and** Android.
- Shared **iOS-inspired Cupertino** vocabulary on both: CupertinoTabBar,
  grouped CupertinoListSection and ListTile, search, segmented controls,
  CupertinoSwitch and Cupertino navigation styles. Do not replace it with
  a responsive website or ship Android-only behavior.
- Use Cupertino on BOTH platforms deliberately, not only when the OS is iOS.
- Show native connection, loading, offline, stale, unsupported and
  unauthorized states, not fake active counts or demo data.
- Respect safe areas, small phones, large accessibility text, dark/light
  contrast, navigation restoration and reduced-motion requirements.
- Keep all existing functioning native workspace and approval flows
  reachable while the new IA is adopted. No destructive server reset.

## Integration truth table: audited from the current branch

| Service | Current secure pilot truth | Correct action |
|---|---|---|
| Codex CLI / IDE | Saved local Codex threads discovered by opt-in worker; resume and supervised turns require official CLI + real sessions | Sessions only when verified on an online capable worker |
| Claude Agent SDK | Verified O-AGENT-owned recorded SDK sessions and supported worker capability | Sessions with independent worker/provider auth; no claude.ai takeover |
| GitHub Copilot SDK | Verified O-AGENT-owned recorded SDK sessions and supported worker capability | Same restrictions as Claude SDK |
| VS Code local projects | Enrolled workspace inventory and scoped Codex CLI/IDE support | Device/projects; not arbitrary live IDE tab control |
| GitHub repositories, Actions and PRs | Connector exists in a separate older native workspace using its own backend/config | Show separate integration, route to old workspace, do not claim private-pilot connection |
| Cursor Cloud | Older connector exists separately; real use needs separate credentials/backend | Show separate integration without claiming current SaaS enrollment |
| ChatGPT consumer/Work browser | No verified third-party API to list/take over arbitrary existing chats and approvals | Official service shortcut only, prominent unsupported note |
| Claude.ai / Gemini consumer chats | No verified takeover API in this project | Official service shortcut only |
| O-AGENT-owned OpenAI/Anthropic API chats | Earlier own-conversation runtime exists with provider API keys | Preserve legacy route; eventual shared authenticated migration |
| Files, screen, PDFs, images, cloud work | Partial older modules, no universally verified end-to-end app flow | Must pass provider-specific acceptance; no pretend buttons |

**Important:** Configuring GitHub or an AI provider inside this ChatGPT
conversation does not grant O-AGENT that user's token or permissions.

## Delivery phases, in priority order

### P0 — restore central agent experience
- [x] Audit existing secure pilot and legacy provider surfaces.
- [x] Document the actual product purpose and integration distinctions.
- [x] Agent directory data model from real worker heartbeats and verified
      session records, never static online statuses.
- [x] Shared Cupertino-style Agents-first navigation and agent directory,
      searchable and available before login as a read-only preview.
- [x] Preserve Sessions, Inbox, Devices, Settings and earlier native workspace.
- [ ] **Physical device acceptance** on an Android phone and iPhone.
- [ ] Validate real Codex resume, Claude/Copilot SDK resume, and approval
      delivery on the owner's signed-in machines.
- [ ] Merge legacy GitHub/Cursor project data through explicitly authorized
      secure endpoints into the same account, instead of a separate UI.
- [ ] Native provider account connections, capability testing and revocation.
- [ ] Agent/session-first composer with real output and tool event timeline.

### P1 — remote working context
- [ ] Real read-only scoped files, code diffs and test output per project.
- [ ] Secure image/PDF/document attachment routing to supported adapters.
- [ ] Visible, consented live view/control of authorized PC apps as a
      distinct computer-control feature (not consumer-site impersonation).
- [ ] Actual push notifications and reliable resume/reconnect/error states.
- [ ] Persistent cross-provider unified session history with data retention.
- [ ] Per-user in-app credentials/connection screens backed by secure vault.

### P2 — hosted reliability and commercial readiness
- [ ] Always-on control plane and isolated cloud workers.
- [ ] iOS signed TestFlight build and Android signed release.
- [ ] Apple account/signing entitlements, device testing and mobile hardening.
- [ ] Security audit, token expiry/revocation, backup/restore, concurrency
      tests, rate limits, rollback and end-to-end acceptance.

## Acceptance gates

1. On both platforms, the first signed-in screen is Agents, not a generic
   inventory screen. Codex, Claude, Copilot, VS Code, GitHub, Cursor and
   ChatGPT appear, with real or explicit unavailable status.
2. Directory indicates session-ready **only** with a verified session AND
   a live, not-revoked, capable enrolled worker. Offline/revoked/missing
   capability does not expose actionable remote control.
3. Codex and SDK session selection navigates to supported real session
   flows. Unsupported providers cannot silently receive prompts or approvals.
4. Existing approvals remain exact-action, authenticated and audited.
5. Empty/unconfigured account states are helpful and do not invent data.
6. Cupertino tab/navigation/search/tiles render under Android and iOS
   Flutter widget/simulator tests, including narrow widths and text scaling.
7. No single UI change triggers an Android APK build. First run full
   Flutter analyze/tests and backend/security CI, then batch one release.
8. iOS code compiling is not an IPA. Release requires a signed Apple
   developer certificate and hands-on iPhone validation.

## Architectural direction

Flutter iOS/Android (Cupertino UX)
    -> O-AGENT authenticated control-plane API
    -> tenant-scoped sessions, approvals, capability reports and events
    -> verified local signed worker / permitted cloud adapter
    -> Codex official CLI/app-server, Claude Agent SDK, Copilot SDK,
       and separately authorized GitHub/Cursor APIs.

Provider consumers without APIs remain external, not fake live-control surfaces.
