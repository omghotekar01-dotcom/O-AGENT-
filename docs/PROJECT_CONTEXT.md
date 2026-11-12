# O-AGENT project continuity

**Repository:** `omghotekar01-dotcom/O-AGENT-`  
**Release branch:** `main` (new work reviewed via feature pull requests)  
**Project name:** O-AGENT / OMIO AGENT HQ  
**Status:** operational Node + gateway development MVP, Flutter Android/iOS Studio and optional server-side AI-provider integration. Not production-ready.

## Mission

An Android-first command centre for real AI-agent operations on authorized laptop and cloud machines: discover agents, submit tasks, inspect actual execution, view real-time events, and approve sensitive actions. The phone is the control surface; durable backend and gateway workers perform execution even when the phone app closes.

## Historical foundation audit (2026-11-12)

The audited foundation branch contains:

- A product README and architecture, security, provider-capability, realtime/audit, and implementation-roadmap documents.
- Typed provider capability and run-state contracts under `packages/contracts/src/`.
- An initial Supabase/Postgres migration covering workspaces, devices, agents, runs, approvals, events, outbox, artifacts and RLS.

**Historical note:** This was true when the foundation branch was first inspected. Subsequent work added the Node control-plane, worker, Flutter clients, tests and server-side provider integration; see current state below.

## Current delivered development features (2026-11-12)

- `apps/control-plane/src/server.mjs`: authenticated operator/worker HTTP endpoints with local JSON persistence.
- `apps/control-plane/src/agent-runtime.mjs`: real OpenAI Responses / Anthropic Messages provider adapters, bounded safe tool loop, three agent profiles, persistent conversation threads. Requires a separately provisioned provider API key in the backend environment; live external calls cannot be verified in CI without the user's credentials.
- `apps/gateway/src/worker.mjs`: outbound-only read-only machine information and human-approved workspace inventory.
- `apps/flutter/lib/ui/studio.dart`: editorial Flutter home, agent profiles, real AI chat, activity and approvals; no dummy providers or connected workers.
- `tests/agent-runtime.test.mjs`: mocked provider/protocol/tool-integration tests. GitHub CI runs Node + Flutter analysis/tests, Android APK and iOS Simulator builds.
- Setup and real-device acceptance tests: [AI setup](AI_SETUP.md) and [MVP runbook](MVP_RUNBOOK.md).

**Not yet shipped:** production identity/RBAC, per-device enrollment, cloud workers, full remote desktop, unrestricted commands, autonomous browser control, provider OAuth, hosted persistence, production deployment, observability platform, signed iPhone IPA.

## Unified project and remote supervisor iteration

The November 2026 follow-up adds the capability-aware **ProjectHub** service, real configured GitHub Actions/PR records, optional official Codex Cloud task snapshots, an approval-gated NEW Codex Cloud task submission capability, preview-only prompt enhancement, project-first Flutter UI and private Tailscale Serve access. The external connected-provider experience is **partial**. Existing ChatGPT Work chats, live managed browser control, document attachments and always-on hosted backend are **not** implemented. See [the clarified product contract](UNIFIED_AI_WORKSPACES.md) and [remote access](REMOTE_ACCESS.md).

## Codex local workspace discovery (new)

The second owner clarification prioritizes **Codex CLI/IDE sessions actually being worked on**, rather than GitHub repo lists or empty Codex Cloud task lists. The optional `codex app-server` JSON-RPC scanner runs on the Windows gateway, reads current account session metadata, groups sessions by `cwd` and shows real project history on Android. Explicit opt-in is separate from Codex Cloud sync. No independent live-session takeover, ChatGPT Work managed browsing, full history or phone-input routing has been implemented. See [Codex CLI workspace setup](CODEX_LOCAL_WORKSPACES.md).

## Remote Codex session control (Nov 2026)

The owner's primary requirement is sending messages into **actual sessions**, streaming the agent's real output, and approving its permissions on Android. The first supervised connector uses official Codex app-server thread/resume + turn/start, backed by worker-verified session and cwd, initial approval, read-only default or workspace-limited edits, provider event timeline and separately gated permission requests. It does not control the ChatGPT consumer website, managed Work browser, or independently active Codex CLI text boxes. See [research and implementation limits](UNIVERSAL_REMOTE_AGENT_CONTROL.md).

## Decisions to preserve

1. Treat OMIO-owned agents, provider-managed sessions and workspace workers as different runtime types.
2. Keep identity, policy enforcement, and task state in the backend. Never rely on the mobile UI for access control.
3. Use authenticated outbound gateway connections, not publicly exposed machine control ports.
4. Make audit events, approval decisions and idempotency durable; notifications alone are not event storage.
5. Never show fake connected providers, running tasks, screen feeds, or success counters.
6. Prefer thin vertical slices that can be exercised against a real backend to broad placeholder UIs.

## Workstream priorities

1. Testable contracts and schema verification.
2. Authenticated control-plane API, persistence and durable event replay.
3. One genuine agent/gateway path with explicit permissions and meaningful errors.
4. Native Android client and web operations console calling actual endpoints.
5. Recovery, observability, provider adapters, and deployment hardening.

## Delivery evidence

For each feature, record: changed files, automated tests and output, supported and unsupported operations, required environment variables, security review notes, and verified GitHub author and committer.

## Inspiration versus functionality

Reference images illustrate a secure API gateway, agent dashboard, approvals, dark/light mobile interfaces, and workspace activity. They are **visual references only**, not evidence that any integration works. Build UI screens from actual API state and show honest empty/error/disconnected states.

## Contributor identity

Use the connected repository owner account `omghotekar01-dotcom`. Requested commit author identity: `Omiiii <omghotekar01@gmail.com>`. Verify actual GitHub author and committer metadata after each commit.
