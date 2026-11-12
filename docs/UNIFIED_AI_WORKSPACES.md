# O-AGENT — Unified AI Workspace Blueprint

Updated: 12 November 2026

## What the owner wants

O-AGENT is a remote supervisory app for **existing running AI systems and their projects**, not only another chatbot. The phone should display real projects, status, agent actions, files, browser view (when technically available), screenshots, permissions and results. A user can type or attach a prompt on the phone, optionally improve it with O-AGENT's own model, then route it to the correct external provider/session using a supported API. The app must remain usable over a network without a USB connection, and cloud work should continue when the laptop is offline.

The requested complete experience is a **target**, not a claim that every provider lets a third party access its managed conversations or browser.

## Non-negotiable product principles

1. A listed project must come from a real authorized provider response or an O-AGENT-owned stored project.
2. A status means a verifiable provider/worker state. Unknown and stale are not running.
3. Buttons to chat, stream a browser, approve or modify an external session appear only when the adapter actually implements those controls.
4. Never inject prompts into unrelated browser text fields by scraping consumer-account sessions or bypassing provider authentication.
5. Keep credentials in backend/OS secure storage; never export browser cookies or saved passwords from the mobile client.
6. Full remote access requires identity and network authorization. Exposing a development bearer-token server on the public Internet is not safe.

## Provider capability matrix — delivered / target

| Surface | Authorized mechanism | Delivered in this branch | Not yet possible here |
|---|---|---|---|
| O-AGENT-owned projects | Existing backend and OpenAI/Anthropic APIs | Create, list, persist, project chat via real provider request | Durable workflows, attachments, full computer execution |
| GitHub repositories / Actions | Official GitHub REST API | Configured repo metadata, latest actual workflow runs, PRs, failures | Controlling external coding agents or browser screens |
| OpenAI Codex Cloud tasks | Authenticated official Codex CLI: cloud list --json | Opt-in task titles/status/URLs, plus creation of a NEW approved Codex Cloud task via authenticated CLI | Replies to existing tasks, interactive cloud browser view, direct provider approvals |
| ChatGPT Work projects/browser | ChatGPT's own hosted Work experience | Explicitly marked unsupported | No verified third-party session-control API for pre-existing Work chats/browser |
| Claude Agent SDK | Documented app-owned SDK process and permission hooks | Planned | Live supervised Claude agent sessions |
| Windows desktop browser/control | Enrolled user-consented local executor | System health/inventory only | Interactive controlled browser capture, WebRTC, remote input |
| Independent cloud runtime | Separate hosted worker, provider API and persistent control plane | Planned | Always-on cloud control plane / queued remote execution |

Official references:
- Codex CLI: https://learn.chatgpt.com/docs/cli/reference
- GitHub workflow runs: https://docs.github.com/en/rest/actions/workflow-runs
- ChatGPT cloud browser: https://learn.chatgpt.com/docs/browser
- Anthropic Agent SDK: https://code.claude.com/docs/en/agent-sdk/overview
- OpenAI file inputs: https://developers.openai.com/api/docs/guides/file-inputs
- Private Tailscale Serve: https://tailscale.com/docs/features/tailscale-serve

## Proposed production architecture

~~~text
Android / iOS  --- authenticated HTTPS --->  O-AGENT API + realtime event service
  |                                             |
  +-- Projects / Runs / Agents / Approvals     +-- Auth / workspace policy
  +-- Rich chat and attachments                +-- Provider capability manifests
  +-- Live events, files, browser view         +-- Durable job orchestration
                                                +-- Database + object store
                                                +-- Secret manager / billing
                                                              |
                                 +----------------------------+----------------------+
                                 |                            |                      |
                            OpenAI / Codex                 Claude SDK             GitHub / MCP
                            official adapters             owned runtime           official adapters
                                 |                            |                      |
                                 +----------------------------+----------------------+
                                                              |
                                            Outbound worker relay (WSS)
                                                 |                 |
                                          Windows agent        Cloud sandbox
                                          (explicit UI        (separate work
                                           approval)            environment)
~~~

Identity: Supabase Auth or equivalent OIDC with device revocation, account scoping and short-lived sessions.
State: PostgreSQL with workspace-scoped projects, runs, messages, provider sessions, action approvals and transactional outbox.
Artifacts: encrypted object storage with authenticated expiring file downloads, separate screenshot/log retention.
Realtime: durable event sequence, incremental sync and SSE/WebSocket notifications. Never infer completion from a sent notification.
Workflows: durable queues/checkpoints, cancellation, budgets, leases, retry and fencing.
Browser: an explicit consented computer-control agent only; scoped capture, private signaling, WebRTC with user authorization. No invisible scraping of ChatGPT Work's managed cloud browser.

These are **design selections requiring deployment and provider authorization**, not software already running in your account.

## Priority roadmap and acceptance gates

### P0 — Fix actual provider reliability

- [ ] Validate real model credentials and model access, not just that a token exists.
- [ ] Display distinct 401/403/429 model/billing/rate-limit responses with a recovery action.
- [ ] Verify real AI messages with the owner's provider account and credits.
- [ ] Make server and worker failures inspectable from mobile.
- [ ] Keep conversations and activity recoverable across app restart and provider outage.

### P1 — Unified real project feed (current development slice)

- [x] Server-owned O-AGENT project create/list and project-chat endpoint.
- [x] GitHub REST repository, real Actions run and PR aggregation (configured repos).
- [x] Explicitly opted-in Codex Cloud task sync from authenticated local CLI.
- [x] Provider capability/unsupported status displayed, stale sync is not called live.
- [x] Mobile Projects landing, status filters, detail views and provider links.
- [ ] Real acceptance test using owner's GitHub and Codex accounts.
- [ ] Built-in browser screen, provider approvals or Codex write controls.

### P2 — Correct cross-provider routing

- [ ] Provider-specific session identifiers, documented write capability and verified OAuth/SDK auth.
- [x] Preview-only AI prompt rewrite endpoint with editable proposed text and target before dispatch; requires working API quota.
- [ ] Real image/PDF/document uploads, validation, encryption, retention and model/provider submission.
- [ ] Reliable streaming of model output and tool/action events, pause/resume and follow-up messages.
- [ ] User-scoped permissions enforced by a server canonical action hash and expiry.
- [ ] Implement Codex Cloud submission using official CLI/SDK only with an explicit target environment and confirmation.
- [ ] Add Claude Agent SDK runtime as a distinct app-owned agent, not as an imitation of claude.ai.

### P3 — Computer/browser supervision

- [ ] Verified Windows agent enrollment, explicit screen-capture indicator and per-device revocation.
- [ ] Encrypted live screen transport and a responsive view-only mode.
- [ ] Controlled browser/IDE/terminal commands inside an approved worker workspace.
- [ ] File preview, artifact download, terminal test output and accurate action audit.
- [ ] No input forwarding without an explicit action grant and verifiable target.

### P4 — Cloud independence and production security

- [ ] Deploy a hardened always-on cloud control plane with external account authorization.
- [ ] Move JSON state to durable Postgres/outbox and encrypt stored assets.
- [ ] Run isolated cloud worker jobs without an online laptop.
- [ ] Secure mobile login, push notifications, per-device keys and backend rate limiting.
- [ ] Security/load/recovery tests and signed Android/iOS production releases.

**Definition of done:** Every feature is observed on a real device/account, with explicit supported capabilities, backend permission enforcement, persisted evidence, failure/reconnect tests and a reproducible acceptance test. Building an APK is not enough.

## New development API contracts

- GET /api/projects : owned + configured GitHub projects + opted-in Codex cloud task snapshots; includes sourceErrors and source capabilities.
- POST /api/projects : create an owned project.
- GET /api/projects/:id : provider details and owned thread where applicable.
- POST /api/projects/:id/messages : real AI prompt **only for O-AGENT-owned projects**.
- GET /api/integrations : connector capability/status list.
- POST /api/workers/:id/codex/sync : authenticated worker-only Codex CLI metadata (disabled by default).
- POST /api/providers/codex/tasks : NEW cloud task requested by operator, must be approved before worker submits via official CLI.
- POST /api/ai/refine : optional rewrite-only AI prompt proposal (no tools/side effects).

The control plane enforces the existing operator/worker development bearer tokens. No real external provider or browser command is fabricated.

## Remote access without USB — two distinct goals

### A. Private phone-to-laptop access today

Tailscale Serve (not Funnel) makes the local API available on a private, authenticated tailnet with HTTPS. It requires a one-time Tailscale login on laptop and phone; **no USB**. Local laptop work stops when the laptop goes offline. See REMOTE_ACCESS.md.

### B. Cloud control when laptop is offline

Requires a separately hosted O-AGENT API, durable DB, auth, an outbound connector that can sync when online, and a cloud worker for jobs that do not need the personal laptop. This has **not** been deployed, and cannot be completed without the user's hosting account/authorization. Do not expose the current static-token MVP publicly.

## Current blockers

- The owner's screenshot shows an actual HTTP 429 AI-provider response. AI chat cannot be called verified until quota/billing/limit issues are resolved with a real provider request.
- The current O-AGENT provider APIs do not expose ChatGPT Work's existing managed browser and chats.
- Provider logins, private repositories and cloud environments require the owner's explicit authorization. O-AGENT cannot copy credentials from a ChatGPT connector into its backend.
- A remote laptop view will require explicit capture/streaming implementation and consent, not an invented screenshot.
