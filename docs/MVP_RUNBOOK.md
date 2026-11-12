# Operational MVP runbook

This repository now includes a **development** control plane, a read-only laptop gateway, a live-data web dashboard, and a native Android control client. It is **not a production-ready remote agent platform**. No LLM integrations, arbitrary shell execution, full remote desktop, cloud worker provisioning, or production identity provider are claimed to work.

## Prerequisites

- Node.js 20 or newer (Node.js 22 recommended).
- A machine running the backend, and a machine running the gateway (they can initially be the same computer).
- For Android: recent Android Studio, JDK 17+, Android SDK 36, and a compatible Gradle distribution.

## Start the backend

From repository root:

```bash
node -e "console.log(require('node:crypto').randomBytes(32).toString('hex'))"
```

Generate **two different** random tokens. In a terminal, set them in environment variables (never commit their values):

```bash
export OAGENT_API_TOKEN='insert-first-random-token'
export OAGENT_WORKER_TOKEN='insert-second-random-token'
npm start
```

The backend binds to `127.0.0.1:8787` by default. The data file is `.local/oagent-data.json` (excluded by `.gitignore`). This development store uses atomic file replacement but **does not support concurrent backend instances, enterprise durability, SQL transactions, or encrypted-at-rest storage**.

## Start the laptop gateway

In a **different terminal** on the same machine:

```bash
export OAGENT_WORKER_TOKEN='insert-second-random-token'
export OAGENT_WORKER_ID='my-laptop'
export OAGENT_WORKSPACE_ROOT='/absolute/path/to/safe/workspace'
npm run worker
```

The gateway makes **outbound requests** to the backend, never opens a remote command port, and currently exposes two capabilities:

- `system_info`: real machine OS/CPU/memory/uptime metadata;
- `workspace_inventory`: up to 100 top-level entries under the configured workspace root, only after approval. Symlinks are labeled and not traversed.

Arbitrary terminal commands, file modification, provider integrations, and remote screens are deliberately **not supported** in this phase.

## Use the web dashboard

Visit http://127.0.0.1:8787 and enter `OAGENT_API_TOKEN`. No test workers or fake task records are seeded. Select a connected worker, request an actual system report, or request the approval-protected file inventory. Status changes and results originate from backend state and gateway execution.

## Use the Android application

Open `apps/android` in Android Studio. Build the **debug** application and run it on an emulator. The default development URL is `http://10.0.2.2:8787` (emulator access to the host's localhost). Enter your real operator token to connect. The app shows live data from the backend when refreshed, submits tasks, and approves/rejects workspace inventory requests.

The **release** manifest disallows unencrypted HTTP. For access from another network, deploy the backend behind authenticated HTTPS/TLS and configure a secure `https://` URL. Never directly expose the development HTTP backend or put these tokens in an APK.

## HTTP contracts (development only)

All operator endpoints require `Authorization: Bearer <OAGENT_API_TOKEN>`. All worker endpoints require `Authorization: Bearer <OAGENT_WORKER_TOKEN>`.

| Method | Path | Use |
|---|---|---|
| GET | `/health` | Public process health (not application readiness) |
| GET | `/api/state` | Registered workers, task state |
| GET | `/api/events?after=N` | Persisted ordered events (up to 200 per page) |
| GET | `/api/stream` | Live SSE updates; reconnect and query events to avoid gaps |
| POST | `/api/tasks` | Create task; requires an `Idempotency-Key` header, 12+ characters |
| POST | `/api/tasks/:id/decision` | `{"approve":true}` or `{"approve":false}` |
| POST | `/api/tasks/:id/cancel` | Cancel only before execution |
| POST | `/api/workers/register` | Register or reconnect worker |
| POST | `/api/workers/:id/heartbeat` | Update worker's last seen timestamp |
| POST | `/api/workers/:id/next` | Claim one queued task |
| POST | `/api/workers/:id/tasks/:taskId/finish` | Report real success or failure |

Example using the operator token:

```bash
curl -H "Authorization: Bearer $OAGENT_API_TOKEN" http://127.0.0.1:8787/api/state
curl -X POST http://127.0.0.1:8787/api/tasks \
  -H "Authorization: Bearer $OAGENT_API_TOKEN" \
  -H "Idempotency-Key: run-system-info-0001" \
  -H "Content-Type: application/json" \
  -d '{"workerId":"my-laptop","kind":"system_info"}'
```

## Verification

```bash
npm run check
npm test
```

GitHub Actions runs these checks on pushes and PRs. The test suite verifies: registration, heartbeat and stale state, task execution lifecycle, approval/rejection, idempotency, cross-worker authorization checks, cancellation limits, and unsupported-operation rejection.

## Known limitations and security gates

1. The MVP uses static operator and worker tokens, not a complete identity/session/device-authentication system. A production deployment requires a real IdP, user/tenant RBAC, key rotation, scoped machine identities, request signing, and revocation.
2. A worker token currently grants access to worker routes across registered workers; it is **not a secure device enrollment mechanism**.
3. Local JSON persistence is for a **single development instance**. Migrate to the existing Supabase/Postgres RLS schema, transactional outbox, and a durable workflow engine.
4. Interrupted running tasks are not automatically retried; recovery, worker leases and fencing must be implemented before production rollout.
5. SSE delivery is live only; use cursor-based event replay on reconnect. Event retention is bounded to 5,000 entries.
6. Web and Android clients refresh actual state. Push notifications and background synchronization are not implemented.
7. Filesystem inventory does not execute commands or recursively access files. Configure only a safe workspace path.
8. The web UI stores the operator token in **tab-scoped sessionStorage**. For production replace this with properly scoped, short-lived credentials and a security-reviewed auth flow.
9. No claim of finished Android compilation, production deployment, or external-provider verification should be made without CI/device evidence.

See `docs/PROJECT_CONTEXT.md`, `docs/SECURITY_BASELINE.md`, and `docs/IMPLEMENTATION_ROADMAP.md` for next phases.
