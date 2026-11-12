# Implementation roadmap and acceptance gates

## Phase 0 — research and architecture baseline

- Research provider API/session capabilities and security standards.
- Freeze entity boundaries, event protocol, state machine, credential policy and provider capability contract.
- Create a versioned architecture/security baseline.

**Gate:** architecture docs and typed contracts reviewed; unsupported capabilities explicitly identified.

## Phase 1 — repository, CI, identity and tenant data

- Establish monorepo layout and protected branch/review policy.
- Add automated format, typecheck, test, dependency and secret-scanning gates.
- Implement Supabase Auth integration and device registration.
- Create tenant-scoped schema and RLS policies for workspaces, projects, agents, devices, connections, runs, approvals and events.
- Add API OpenAPI contract and typed client.
- Add native Android shell and web admin shell with real auth and empty states.

**Gate:** cross-tenant tests pass; auth revocation and session expiry behave correctly; zero mock production data.

## Phase 2 — durable events and realtime sync

- Implement transactional outbox and durable event sequences.
- Implement private Broadcast subscription, snapshot/cursor sync, replay, deduplication and offline cache.
- Add OTel trace propagation across API, workflows, adapters and workers.

**Gate:** disconnect/reconnect test proves no missed/duplicated user-visible activity; events are persisted before broadcast.

## Phase 3 — first real agent/provider vertical slice

- Choose one provider with available credentials and supported API/SDK.
- Implement connection authorization, health check, capability manifest, real session creation, chat streaming, event persistence, cancellation and recovery as supported.
- Add provider cost/quota metadata where supplied.

**Gate:** a task can be created, run, observed, stopped and recovered using a real provider account; no simulated response path.

## Phase 4 — durable orchestration and cloud workspaces

- Implement Temporal workflow definitions and worker activities.
- Add isolated cloud workspace provisioning, filesystem, terminal and browser tools.
- Implement resource budgets, network egress rules, snapshots/checkpoints and cleanup.

**Gate:** cloud run continues if Android and personal laptop are offline; retry/recovery does not duplicate side effects.

## Phase 5 — enrolled Windows worker and live workspace

- Build signed Windows worker/tray app that runs UI automation in the logged-in interactive session.
- Enroll device keys, heartbeat, outbound authenticated control channel, lease/fencing and revocation.
- Add WebRTC screen streaming, authenticated signaling, TURN fallback and permissioned input takeover.

**Gate:** remote test over a separate network demonstrates encrypted live screen/control; laptop-off state is truthful; revoke worker instantly blocks commands.

## Phase 6 — provider expansion and agent coordination

- Add official provider adapters one at a time: Anthropic, GitHub Copilot, Gemini, and other providers only after current API/terms review.
- Add capability-aware delegation/subagents, MCP server registry and project context transfer.
- Add per-provider quotas, budgets, beta labels and failure modes.

**Gate:** each connector passes its own contract tests and only advertises implemented controls.

## Phase 7 — hardening and production readiness

- ASVS/MASVS verification, static/dependency scans, dynamic/API tests, mobile security tests and external penetration test.
- Load, soak, reconnect, workflow recovery, backup-restore and disaster-recovery drills.
- Retention, privacy, incident response, key rotation and operational runbooks.
- Release only with dashboards, alerting, support/runbook and tested rollback.

**Gate:** all release-blocking security, reliability and acceptance tests pass. No unsupported claim of certification or 100% uptime.

## Definition of done for every feature

1. Real API/backend implementation exists.
2. Authentication and authorization are enforced server-side.
3. Capability and permission checks determine whether control is available.
4. State transition and event are persisted transactionally.
5. Idempotency prevents duplicate side effects.
6. UI reads backend state and displays freshness/error/offline semantics.
7. Event replay works after disconnection.
8. Secret redaction and audit records are verified.
9. Positive, negative, failure and recovery tests exist.
10. User-facing status accurately describes what the feature can and cannot do.
