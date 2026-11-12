# OMIO AGENT HQ

**A native Android-first command centre for a real, observable AI workforce.**

OMIO AGENT HQ manages three distinct execution modes:

1. **OMIO-managed agents** — agents whose tools, permissions, workflows and execution are operated by OMIO.
2. **Provider-managed sessions** — sessions created through supported APIs/SDKs from OpenAI, Anthropic, GitHub, Google and other providers.
3. **Workspace workers** — registered Windows or isolated cloud workers that operate explicitly authorised terminals, browsers, IDEs and files.

## Non-negotiable engineering rules

- No fake provider connections, fake agent activity, fabricated live screens, placeholder run results or simulated completion states in production.
- A visible action must call a real backend operation or be disabled with a clear explanation.
- A connection is `connected` only after real authentication and a provider health/capability check.
- A provider capability is not assumed. Every adapter must publish what it actually supports.
- Persist state and events before announcing success to a client.
- The backend is the source of truth. Android and web are control surfaces, not agent execution hosts.
- Local Windows work requires an online, enrolled worker in the logged-in interactive user session.
- Cloud work can continue without the phone or laptop only when the required workspace, files, tools and credentials exist in the cloud.
- Secrets never enter source control, client builds, prompts, logs, screenshots or telemetry.
- Production claims require automated tests and observable evidence. No claim of perfect security, unlimited compute or 100% uptime.

## Current repository status

This branch is the **foundation baseline**: researched architecture decisions, security requirements, realtime/event rules and typed provider/run contracts. It is not yet a deployed product. Live integrations must be implemented and verified in subsequent phases; no mock data should be added to conceal that status.

## Architecture at a glance

- Android: Kotlin, Jetpack Compose, Material 3, Android Keystore, BiometricPrompt, Room, WorkManager, FCM.
- Web administration: Next.js + TypeScript.
- API: typed TypeScript service with OpenAPI contracts.
- Identity/data: Supabase Auth + Postgres + Storage with tenant-aware RLS.
- Durable orchestration: Temporal workflows and separately deployed workers.
- Realtime: durable event log + transactional outbox; private Supabase Broadcast for app updates; authenticated worker relay using Cloudflare Durable Objects or an equivalent stateful relay.
- Screen/control: WebRTC (DTLS-SRTP) with authenticated signaling and explicit session authorization.
- Local execution: signed Windows worker running in the interactive logged-in user session.
- Observability: OpenTelemetry plus durable domain events and append-only audit records.

See [Architecture decisions](docs/ARCHITECTURE_DECISIONS.md), [Security baseline](docs/SECURITY_BASELINE.md), [Realtime and audit contract](docs/REALTIME_AND_AUDIT.md), [provider capability matrix](docs/PROVIDER_CAPABILITY_MATRIX.md), [provider contracts](packages/contracts/src/provider-capabilities.ts), and the full [implementation roadmap](docs/IMPLEMENTATION_ROADMAP.md).

## First release gates

A feature is not done because a screen renders. It is done when the real backend operation is implemented, permission-checked, durably recorded, testable, recoverable and accurately represented in the UI. Cross-tenant access, credential leakage, approval mismatch, duplicate side effects, worker disconnect/reconnect and recovery tests are release blockers.
