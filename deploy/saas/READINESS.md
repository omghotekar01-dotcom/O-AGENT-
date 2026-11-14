# O-AGENT: evidence-based readiness ledger

**Status:** free-first, private self-hosted pilot candidate. **Not** a production SaaS or universal native-control product.

This ledger is intentionally stricter than a feature checklist. Every item distinguishes code shipped, automated verification, real-device acceptance and remaining external dependencies. Never treat a successful `/health/ready` response or a GitHub Actions check as evidence that a personal account or laptop has been connected.

## A. Implemented and covered by automated repository tests

| Area | Implementation | Automated acceptance |
| --- | --- | --- |
| Per-user identity | OIDC access token validation, exact issuer/audience/client and scoped access | Unit tests, real Keycloak CI token smoke |
| Tenant data isolation | PostgreSQL 16 FORCE RLS, non-privileged API DB role, scoped transactions | Real PostgreSQL multi-user tests and forbidden cross-tenant access |
| Device enrollment | Device-generated Ed25519 key, owner-confirmed fingerprint, replay nonce protection and revocation | Signed HTTP integration, crypto replay tests |
| Agent request/approvals | One-time exact digest, time limits, explicit approve/deny, leases, no silent tool authorization | API/database and worker tests |
| Failure recovery | Lease expiration moves uncertain work to needs_recovery; owner confirms non-replay resolution | PostgreSQL and worker tests |
| Private HTTPS | Loopback Caddy reverse proxy through user-operated Tailscale Serve | Disposable container smoke; **not yet a physical phone** |
| Private pilot identity | Keycloak realm import, audience mapper, explicit subject mapper, PKCE client | Real Keycloak OIDC scope/token test |
| Free browser UI | Responsive dashboard, activity, devices, inbox, PWA install, optional Web Push | Static UI, API and push isolation tests |
| Owner data controls | Audit history, scoped JSON export, typed server-data deletion | Database tenant isolation and UI tests |
| Safe operation | Bounded data/errors, quotas, disabled unauthorized provider actions, manual recovery | API and worker regression tests |
| Encrypted backups | Streaming AES-256-GCM encrypted PostgreSQL database archives and guarded restore | Cryptographic tamper tests; disposable database backup/restore smoke |
| Simpler setup | One-command local starter, secret generation, conflict-safe Tailscale Serve and doctor | CI validation and simulated setup/failure tests |
| Existing app compatibility | Legacy preview preserved, Flutter HTTPS launcher, existing backend and Windows launcher | Flutter analyze/tests, backend tests, Windows launcher CI |

Where a check has not passed at the latest commit, see GitHub Actions and do **not** call the item verified. The matrix describes intended acceptance coverage, not a claim of perpetual pass status.

## B. Implemented but MUST be physically accepted before external users

- Connect a real Windows laptop (Docker Engine, Node.js 22.12+, Tailscale with HTTPS and MagicDNS) and run `deploy/saas/free-pilot/start.cmd`. On macOS/Linux use `node deploy/saas/free-pilot/start.mjs`.
- Run `node deploy/saas/free-pilot/doctor.mjs`, address every [FIX] entry, and verify the site from a real phone signed into the same private tailnet.
- Change the temporary generated `pilot-owner` password and enable MFA; perform real sign-in, sign-out, token expiration and interrupted network acceptance.
- Enroll a personally trusted dedicated worker from the installed project, check the fingerprint, verify heartbeat, revoke and re-enroll.
- Confirm real permission requests and denial are reflected promptly on mobile; test Web Push permissions, background notifications, reconnection and expired approvals on the chosen Android/iOS browsers.
- Run a disposable project through read-only inventory first, then an actual supported provider-native turn with user-authenticated SDK credentials. Verify exact before/after files, approvals, no unrequested writes, shutdown and recovery behavior.
- Create an encrypted backup, copy it to a different storage device, restore into a **disposable** pilot and compare data. Protect the passphrase separately.
- Confirm a laptop sleep, restart, lost internet, revoked key, changed Tailnet address and corrupted database each produce useful user-facing diagnostics.

## C. Code/infrastructure/business gates NOT yet completed

These cannot truthfully be marked ready merely by writing code.

| Gate | What it requires | Responsibility |
| --- | --- | --- |
| Public commercial deployment | Commercial-use hosting and network policy, HTTPS domain, managed DB and secret manager | Accounts/funding plus deployment work |
| Organization/team SaaS | Invite flow, tenant membership, role-based authorization, enterprise SSO, admin policies and robust lifecycle | Engineering and organizational decisions |
| Per-tenant hosted worker isolation | Real isolated workers, protected provider credentials, quotas, network egress limits, secure image rollouts | Cloud provisioning and review |
| Native third-party approvals | Official supported SDK/protocol authorization, real subscribed provider accounts, permissions supported by that provider | Provider constraints + account-side consent |
| Universal website tab takeover | No verified official universal API for arbitrary ChatGPT Work/Claude website/Cursor tabs | Cannot be promised |
| Signed mobile/store release | Production mobile API integration, signing keys, device acceptance, store/distribution eligibility | Engineering + user-controlled signing |
| Production resilience | SLO, telemetry, incident response, backups/restore rehearsal, zero-downtime migrations, abuse controls | Real deployment and operational resources |
| External security, privacy and compliance | Threat model, penetration testing, data retention/deletion policies, DPA/ToS/privacy, regional legal review | Independent expert validation |
| Commercial onboarding and payments | Billing provider, cost/usage metering, payment/quotas, support and refund workflows | Startup decisions and accounts |

## D. Lowest-cost order of operations

1. Keep your current APK and `main` untouched. Finish private-pilot code and automated acceptance on draft PR #32.
2. Have the owner perform **one consolidated setup**: install Docker/Node/Tailscale, sign in on laptop + phone, choose the enrolled project root and log into any official provider SDK to be controlled.
3. Use **private Tailscale Serve** and the home-screen PWA before spending on public cloud or app-store releases. Personal/free service eligibility must be confirmed from the vendors before any commercial rollout; free cloud inference is not assumed.
4. Physically verify one end-to-end prompt, streamed status, exact owner permission, successful result, deliberate denial, disconnected worker, and revoked device **without** relying on mock state.
5. Only after verified private acceptance, decide whether to spend on a public commercial control plane, isolated workers and signed mobile binaries.
6. Do not publish customer signup, accept payments or claim arbitrary native provider-session takeover until the respective gates are proven.

## E. Final owner-only contribution bundle

Everything below is postponed until the code is stable enough for acceptance. **Never put credentials in GitHub, screenshots, chats or the source tree.**

- Install current Node.js, Docker/Desktop or Compose and Tailscale on an owner-controlled computer; join both laptop and phone to the same tailnet.
- Generate local secrets with the one-command starter. Keep `.env.local` on the machine only.
- Sign in using the temporary private owner credential, immediately change password and enable MFA.
- Select the project folder on the computer and approve its device fingerprint via the dashboard. Turn on Web Push only if desired.
- Sign into selected, officially supported provider CLI/SDK runtimes in the worker's own local environment. Do not share cookies, OAuth tokens or API keys in chat.
- Test on physical laptop and phone; inspect real file changes and approvals; store an encrypted backup off-machine.
- Only for later commercialization: arrange real domain, identity, hosting, provider approvals, legal/security review and distribution credentials. No payment required for code review or private-PWA testing, subject to the vendor's free-use terms.

## F. Release rules

- **Private pilot candidate** = source and integration smoke pass; still needs real-device acceptance.
- **Beta ready** = phone/laptop/provider acceptance plus recovery and backup restore documented; not commercial multi-tenant.
- **Production ready** = team isolation, infrastructure, independent security review, reliable deployment and support exercised in live conditions.
- **Never claim 100% error-free**. Require observable tests, documented limitations and mechanisms to recover from failures.
