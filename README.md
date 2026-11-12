## One-click Windows startup (recommended)

If you use Windows, **[follow the 1-time setup guide](docs/ONE_CLICK_WINDOWS.md)** and double-click `O-AGENT.cmd` in this repository. The launcher stores tokens under your Windows account using DPAPI, starts the real Node backend and laptop gateway, checks that your machine is online, establishes the USB ADB bridge when available and opens the local dashboard. Subsequent runs require just one double-click. To stop, use `STOP-O-AGENT.cmd`.

The latest Flutter APK also offers **opt-in “Remember this device”**, protecting the operator token with Android Keystore/iOS Keychain to reconnect without re-entering it. Model-provider keys remain on the backend only. No credentials are stored in GitHub.

## O-AGENT Studio — AI agents + Flutter mobile (November 2026)

**[Start here: real AI provider setup and testing](docs/AI_SETUP.md).** The development backend now includes an authenticated model integration with OpenAI Responses API or Anthropic Messages API (choose one and provide your own server-side API key). Conversation threads are persisted locally; the model can use an allowlisted tool set to inspect real registered machines and tasks, request system health, and request a human-approved workspace inventory. No provider keys are shipped in APKs.

**Flutter Android/iOS** now opens a purpose-designed, editorial agent studio with **Home, Agents, Chat, Activity and Approvals**. Chat messages are sent to the real provider from the laptop backend. Agent profiles are scoped prompts, not fake autonomous cloud agents. Tool execution stays bounded and user-controlled.

A successful Flutter APK build or a configured-key flag is not proof that your external provider key works: perform the [real-device acceptance checks](docs/AI_SETUP.md) on your Windows laptop and Android phone. Chat requires an API key with active provider access and may incur charges.


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

## Working development MVP (new)

The foundation branch now also includes a **real, local-development vertical slice**:

- [Control-plane API](apps/control-plane/src/server.mjs): authenticated operator and worker endpoints, persistent JSON state, an ordered event feed and task approvals.
- [Outbound laptop gateway](apps/gateway/src/worker.mjs): reports actual system data and an approval-protected top-level workspace inventory; **no arbitrary commands**.
- [Web dashboard](apps/control-plane/public/index.html): connected machines, actual task records, task submission and approval decisions.
- [Android Compose client](apps/android): native UI for machines, task submission, and approvals using actual backend endpoints.
- [Automated control-plane tests](tests/control-plane.test.mjs) and CI workflows.

**How to run:** [MVP runbook](docs/MVP_RUNBOOK.md). **Current state and boundaries:** [Project context](docs/PROJECT_CONTEXT.md).

This is **not the complete O-AGENT product**. Production identity/device enrollment, Supabase-backed orchestration, live remote desktop, cloud workers, provider SDK adapters, MCP connections, and background push notifications remain future work. A reference design or UI screenshot is not evidence that those capabilities are implemented.


## Flutter mobile application (Android + iOS)

The preferred cross-platform mobile client is now in **[apps/flutter](apps/flutter/README.md)**. It connects to the real O-AGENT development control plane and supports machine status, system-information tasks, approval-protected workspace inventories, execution history, and task decisions.

- [Flutter app source](apps/flutter/)
- [Setup instructions and compatibility notes](apps/flutter/README.md)
- [GitHub Actions builds and downloads](.github/workflows/flutter-mobile.yml): Flutter tests, Android debug APK, and unsigned iOS Simulator package.

To generate the native platform scaffolds locally, run `flutter create --platforms=android,ios --org com.omiiii --project-name o_agent_mobile .` in `apps/flutter`, then `dart run tool/prepare_platforms.dart`. Use Flutter's official build tools to run the application.

**Scope:** This is a functioning *development* client for the backend capabilities that currently exist. It is not a finished AI-agent cloud platform; it does not claim to provide production authentication, AI chat, desktop screen streaming, arbitrary remote shell access, or live cloud orchestration. The earlier native Kotlin prototype remains in `apps/android` for continuity.

