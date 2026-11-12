# Architecture decisions

**Status:** baseline for implementation; re-evaluate choices when provider/runtime capabilities or deployment constraints change.

## Product boundaries

OMIO models these as separate entities, even when the UI presents one unified agent directory:

- **Agent definition:** versioned instructions, tools, policies, model configuration and memory configuration.
- **Agent run:** one durable unit of work with its own lifecycle, budget, permissions, workflow and event history.
- **Provider session:** an external session whose lifecycle/control API belongs to the provider.
- **Execution workspace:** a cloud or local environment that runs commands, browser automation, code and files.
- **Device/worker:** an enrolled execution endpoint with its own identity, health and capabilities.

A connected provider session does not imply desktop access. A local IDE connection does not imply the provider exposes its internal session. The capability manifest prevents the UI from inventing unavailable controls.

## Runtime architecture

1. **Android client:** native Kotlin/Compose app for onboarding, agent directory, chat, run monitoring, workspace view, approvals, connection management and security settings.
2. **Web admin:** Next.js/TypeScript management surface using the same API and authorization model.
3. **Control-plane API:** validates user/device/session identity, tenant membership, policy, command idempotency and provider capabilities.
4. **Identity and data:** Supabase Auth and Postgres. Every tenant-owned table is protected by RLS; service-role/secret credentials remain server-only.
5. **Durable orchestration:** Temporal workflows own long-running lifecycle, retries, signals, timers, cancellation, checkpoints and recovery. HTTP handlers never host long-running agent loops.
6. **Provider adapters:** one adapter per documented provider API/SDK/auth mode. Adapters expose a capability manifest and preserve provider session IDs.
7. **Execution plane:** least-privilege cloud workspaces and an enrolled Windows worker. A worker receives scoped, expiring leases and executes only policy-approved commands.
8. **Worker relay:** long-lived authenticated outbound connections, coordinated by a stateful relay. Do not expose laptop SSH/RDP ports to the public internet by default.
9. **Screen transport:** WebRTC media with DTLS-SRTP and authenticated signaling. Use TURN where direct connectivity fails. Decide explicitly whether an SFU may decrypt media; add E2EE if the relay must not access screen content.
10. **Observability:** OpenTelemetry trace/metric/log correlation plus a durable domain event and audit store. Telemetry is not the authoritative event database.

## Data flow

- Client submits a command with an idempotency key and expected run/session version.
- API authenticates the account and device, checks tenant/project/agent permissions, validates capability and evaluates policy.
- A high-risk action creates an approval bound to the exact target and canonical argument hash.
- Accepted command is persisted with an outbox event in the same database transaction.
- Dispatcher starts/signals a durable workflow.
- Worker/provider adapter receives a time-limited lease and fencing token, executes one bounded operation and returns a structured result.
- Result, state transition and domain event are persisted before notification.
- Private realtime message wakes clients; clients fetch the authoritative event sequence after their last cursor.
- UI renders only persisted state and actual provider/worker events.

## Cloud versus local execution

- Cloud work uses a provisioned cloud workspace and can continue when Android and the personal laptop are offline, subject to cloud provider/worker availability.
- Local work runs only in an enrolled Windows worker's interactive logged-in session. If the laptop is offline, the run transitions to `waiting_for_device`; it must not pretend to keep operating.
- Moving a task from local to cloud requires provisioning/transferring the workspace and verifying required files, dependencies, credentials and permissions. This is a new execution target, not silent failover.
- Windows interactive desktop automation must run in the user's interactive session, not in Session 0 as a normal Windows service. A separate service may handle noninteractive privileged operations only with narrowly scoped IPC and explicit policy.

## Stack decisions

| Concern | Baseline |
|---|---|
| Android | Kotlin, Jetpack Compose, Material 3, Room, WorkManager, Keystore, BiometricPrompt, FCM |
| Web | Next.js + TypeScript |
| API | TypeScript + Fastify or NestJS + OpenAPI |
| Identity/data | Supabase Auth + Postgres + Storage, strict RLS |
| Workflow engine | Temporal |
| Provider/model SDKs | Official provider SDKs; Vercel AI SDK only where useful for model streaming/common calls |
| Event notifications | Supabase private Broadcast |
| Stateful worker relay | Cloudflare Durable Objects or equivalent |
| Live screen | WebRTC + authenticated signaling |
| Isolated execution | Dedicated cloud workers/sandboxes; Windows cloud VM for Windows-only apps |
| Observability | OpenTelemetry + domain event store |

Do not make Vercel Sandbox a synonym for a persistent remote Windows desktop; it is an isolated code-execution primitive. Do not make Vercel eve the v1 orchestration core while its release channel remains pre-stable. Re-evaluate after stable release and review.

## Provider integration policy

Use official APIs, SDKs, OAuth or provider-supported browser workflows. Never scrape personal app sessions, bypass MFA/passkeys/CAPTCHA, spoof clients or claim undocumented controls. The adapter must expose authentication method, scopes, quotas, beta/preview status, supported operations and unsupported operations.

## UI truthfulness policy

- A button is rendered only when the relevant capability and permission are available.
- Otherwise show a disabled control with a precise reason, or omit it.
- Loading, stale, disconnected, degraded, expired and error states are explicit.
- Empty states are real empty states; no seed/fake agent counts in production.
- “Live” is shown only while a live transport is open and receiving recent frames/events.
- A screenshot, command log and file diff are separate evidence types. Do not infer one from another.
