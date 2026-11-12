# O-AGENT product requirements and acceptance matrix

**Source:** user-provided O-AGENT master specification and visual references (2026-11-12).  
**Scope:** Android-first personal command centre for authorized AI agents and machines. This document is requirements research, not proof that all capabilities exist.

## Product intent

From an Android phone, an authenticated operator should be able to enumerate enrolled agents and machines, submit real tasks, view truthful progress, inspect real outputs, approve sensitive actions, and retrieve results after disconnecting from the app. Execution belongs to a server, cloud worker or installed laptop gateway, not the Android UI.

## Functional requirements

| ID | Feature | Required behavior | MVP status |
|---|---|---|---|
| FR-01 | Account login | Verified user identity, revocable sessions, device identity | Not implemented; static dev tokens only |
| FR-02 | Device enrollment | Pair machines with scoped credentials, revoke individually | Partial; development registration without secure enrollment |
| FR-03 | Machine visibility | Show recent heartbeats and offline states | Implemented for development worker |
| FR-04 | Agent directory | List registered agents, capabilities, runtime, health | Contracts only; not operational |
| FR-05 | Task submission | Authorized, idempotent, persisted task creation | Implemented with two read-only task types |
| FR-06 | Remote execution | Explicit authorized tool calls and streamed results | Partial; outbound worker can report system and directory info |
| FR-07 | Human approvals | View exact action/target, approve or reject once | Partial; inventory approval, production canonical-action binding pending |
| FR-08 | Background work | Continue work while phone is closed | Backend-worker lifecycle supports this when both processes stay online; no durable workflows yet |
| FR-09 | Realtime feed | Ordered persisted event stream, gap replay | Partial; HTTP cursor feed and live SSE, no durable transactional outbox |
| FR-10 | Chat | Agent-specific conversations, streaming and cancellation | Not implemented |
| FR-11 | Provider adapters | Real OpenAI, Anthropic, Gemini, etc. using official APIs | Research/contracts only |
| FR-12 | MCP integration | Registered tools with granular policy, auditing | Not implemented |
| FR-13 | Workspace browser | Scoped files, real terminal and diffs as separate views | Partial; top-level metadata inventory only |
| FR-14 | Screen sharing | Authenticated WebRTC screen transport and controlled input | Not implemented |
| FR-15 | Cloud execution | Persistent isolated workers with budgets and retries | Not implemented |
| FR-16 | Push notifications | Actionable Android notifications | Not implemented |
| FR-17 | Audit exports | Filterable, secret-redacted immutable domain audit | Partial; local bounded event log |
| FR-18 | Artifacts | Authenticated output download and retention | Not implemented |
| FR-19 | Multi-agent collaboration | Delegation and dependency tracking | Not implemented |
| FR-20 | Integrations and secrets | Scoped encrypted provider credentials and revocation | Not implemented |

## Required UI states

The UI must never infer that an operation succeeded from a button tap. Each action has loading, success, error, unauthorized, unsupported and disconnected states. The dashboard must show an empty machine list when no worker has enrolled. The approvals screen must show actual pending requests. A live screen is distinct from logs, screenshots and files.

Visual direction from reference images: Android-first polished cards, light and dark palettes, clear navigation for Home/Agents/Tasks/Approvals/Settings, readable typography, actionable approval cards, and restrained metrics. The complex microservice image is an architectural **reference**, not a mandate to deploy Kafka, Istio and many databases during the first release.

## Non-functional requirements

1. **Security:** TLS, server-side authorization, individual machine identities, scoped tools and secret-redacted logs; high-risk actions default deny.
2. **Reliability:** durable ownership of runs, idempotency keys, single-decision approvals, explicit cancellation semantics, bounded retries and failure recovery.
3. **Observability:** sequence-numbered event log, trace correlation, request IDs, actual worker heartbeats and run outcomes.
4. **Privacy:** tenant isolation, data retention and export/deletion policy, encrypted credential references, no secret values in mobile bundles.
5. **Responsiveness:** mobile UI should remain usable on weak networks, and page updates must not block task execution.
6. **Scalability:** avoid app-imposed tiny agent limits; use resource budgets and infrastructure-based quotas.
7. **Accessibility:** meaningful labels, readable contrast, keyboard navigation where applicable, large touch targets.
8. **Cost:** track per-provider tokens/usage, cloud VM idle time, queue costs and log retention; do not promise free unlimited usage.

## Acceptance tests before production

- An unpaired machine cannot claim tasks; a revoked device loses access promptly.
- A logged-in user cannot read another workspace's agents, events, approval records or artifacts.
- An approved action must match a canonical hash of its arguments, tool, target, user, run version and expiry.
- Two concurrent claims cannot execute the same non-idempotent operation twice.
- Reconnect replays events after the last acknowledged sequence without inventing duplicates.
- Closing the phone does not cancel server-owned work; shutting off the laptop correctly interrupts local execution.
- Secrets do not appear in APK resources, logs, events, crash reports or screenshots.
- A provider adapter exposes only verified supported operations and clearly reports plan/region/auth limitations.
- An offline worker is shown as offline rather than running; any stuck run requires an explicit recovery path.
- Every functional UI control corresponds to a tested backend endpoint.

## Implementation boundaries and phases

**Implemented development slice:** Node control plane, events, two task capabilities, read-only laptop worker, web dashboard, native Android client, tests and runbook.

**Next required work:** Supabase Auth and tenant-scoped database persistence, per-device gateway credentials, durable orchestration and recovery, real provider adapter, secure mobile session flow and deeper tests. After these, implement live workspace, WebRTC control, cloud workers, MCP, notifications and rollout hardening.

## Canonical references

- [Existing architecture decisions](ARCHITECTURE_DECISIONS.md)
- [Security baseline](SECURITY_BASELINE.md)
- [Realtime event and audit contract](REALTIME_AND_AUDIT.md)
- [Provider capability matrix](PROVIDER_CAPABILITY_MATRIX.md)
- [Roadmap and release gates](IMPLEMENTATION_ROADMAP.md)
- [Current repository audit](PROJECT_CONTEXT.md)
- [Operational MVP runbook](MVP_RUNBOOK.md)

Every status in this document must be re-verified as code changes.
