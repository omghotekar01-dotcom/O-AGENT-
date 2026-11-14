# O-AGENT release-readiness matrix — 14 November 2026

This is an **evidence-based engineering checklist**. The pilot is not a public, multi-customer SaaS, and no version is promised to be 100% free of defects. An item is green only after its exact acceptance criterion is demonstrated; unit tests, a Docker boot, a live provider account, and a real-device trial are *different* evidence levels.

**Delivery strategy:** complete every task that can be developed and tested through the repository before the owner is asked for infrastructure, credentials, domain access, device-side consent or payment. Request all remaining owner contributions **once, in a consolidated acceptance session**. Never put private keys, identity secrets or provider passwords into issues, PRs, screenshots, chat or GitHub source.

## A. Implemented engineering foundations

| Gate | Implementation and evidence | Current classification |
| --- | --- | --- |
| A01 Identity | OIDC JWT signature/issuer/audience/client/scope checks; browser authorization-code PKCE, exact redirect, IdP logout support | Implemented, automated tests; full browser sign-in on real device pending |
| A02 Tenant isolation | PostgreSQL 16 FORCE RLS for devices, runs, approvals, events, push and audit; separate runtime/migrator roles; cross-tenant tests | Automated PostgreSQL security tests |
| A03 Device trust | Ed25519 per-device signing key, fingerprint-checked owner enrollment, 256-bit expiring pairing, nonce replay rejection and revoke | Automated tests; physical enrollment pending |
| A04 Agent work | Explicit run approval, exact action digest, provider tool permissions, time-bound leases, no automatic replay, cancellation and interrupted-run recovery | Automated backend/worker tests; real SDK sessions pending |
| A05 MCP | Authenticated, scoped Streamable HTTP MCP interface; request-only supervised runs, no direct automatic tool approval | MCP protocol and server tests; external MCP client acceptance pending |
| A06 Mobile controls | Responsive web command center, signed-in activity and audit lists, device controls, explicit permission dialogues, phone-installable web app | Automated web integrity checks; real mobile usability pending |
| A07 Notifications | Opt-in Web Push with locally generated VAPID keys, privacy-preserving alerts, per-tenant subscription storage and explicit unsubscribe | Automated privacy/security checks; delivery on physical phones pending |
| A08 Private networking | Self-hosted Keycloak/PostgreSQL/API/Caddy; loopback gateway and Tailscale Serve; no Funnel or router port forwarding | Real Compose integration smoke; live personal tailnet pending |
| A09 Recovery | AES-256-GCM encrypted backup streams, authenticated before restore, no plain SQL dumps written by backup helper | Cryptography tests pass; destructive restore drill on spare volume pending |
| A10 Database evolution | Forward-only checksum-validated, advisory-locked SQL migrations and legacy schema upgrade | PostgreSQL tests; upgrade/rollback drill in live pilot pending |
| A11 Data lifecycle | Server-side erasure of verified personal tenant, token/device invalidation, minimal audit view, expired ephemeral nonce pruning | Automated tests; provider/local-file and backup deletion remain separate |
| A12 Development safety | Draft feature branch, CI regression checks, optional container smoke, superseded-job cancellation, explicit no-APK-build rule | GitHub Actions evidence on each tested commit; latest head must be checked before merge |

**Important:** The Flutter application is a separate legacy private-preview client with an HTTPS command-center launcher. It is **not** yet a fully rebuilt production SaaS-native Android/iOS app. The web PWA is the lower-cost mobile control path for the initial pilot.

## B. Free-first personal pilot: final one-time owner acceptance

Do **not** perform these steps through an untrusted shared computer, and do not send credentials to a developer or chatbot. Each step will be requested together only after all available code checks are green.

| Gate | Owner action at the final handoff | Acceptance record |
| --- | --- | --- |
| B01 Computer | Windows machine with enough RAM/storage, Node.js 22.12+, Docker Compose, trusted filesystem and stable connectivity | Actual install versions and `node doctor.mjs` checks |
| B02 Tailnet | Install Tailscale on computer + phone, enable MagicDNS/HTTPS certificates, ensure both connect to owner's private tailnet | Browser loads private HTTPS URL over mobile network, no public exposure |
| B03 Identity | Run private starter, use generated first-login credentials **on your own device**, set new password/MFA | Real OAuth login + logout and `/v1/me` from mobile browser |
| B04 Worker | Start quickstart on a disposable project, inspect the exact fingerprint and approve the correct laptop | Signed heartbeat + workspace inventory + phone-visible device |
| B05 Approval | Submit one read-only supervised run, review a precise action hash, deny and approve separate tests | Correct one-time decision and actual execution/history |
| B06 Native providers | Authenticate each desired supported SDK/CLI **directly with its vendor**, verify account eligibility, consent and quotas | Genuine provider session ID, continuation, tool approval, error handling |
| B07 Notifications | Opt in on a compatible phone and verify a genuine approval alert while browser is closed | Actual notification delivered; opening it leads to signed-in approval screen |
| B08 Recovery | Stop/restart worker, test offline status, network loss, expiry, revocation, and one **disposable** encrypted backup/restore | Written pass/fail evidence; no duplicated edits or stale approvals |

Steps B01–B08 require access to physical devices and consent and are **not implied** by CI status. If a vendor requires an API key, token, plan, or payment, the user enters it into that vendor's official sign-in system or a trusted device-local secret store; never into source code.

## C. Public startup SaaS release blockers — engineering and business

| Gate | Must exist before paid multi-customer availability | Current state |
| --- | --- | --- |
| C01 Accounts and teams | Signup protection, verified email/MFA, organization membership, invite/removal/roles, tenant transfers, admin recovery | Not implemented as multiuser organizations (v1 is one verified identity → one private tenant) |
| C02 Execution isolation | True separate tenant workers or VMs, CPU/RAM quotas, restricted filesystem and network egress, no mixed customer provider sessions | Per-worker image/reference exists; automated cloud tenant sandbox provisioning not implemented |
| C03 Trust and data | Managed secrets/KMS, rotation, encryption at rest in production, audit retention, abuse response, privacy/deletion policy, backup expiry | Foundation only; external security/legal acceptance required |
| C04 Hosted service | Owner-controlled HTTPS domain, production hosting, managed PostgreSQL backups, restore drill, health/alerts, incident response, DNS and TLS ownership | Not deployed; personal laptop pilot requires machine online |
| C05 Cost protection | Account quotas, per-provider budgets, billing/payment integrations, spend alerts, chargeback and abuse controls | Basic run caps implemented; real provider billing and customer charging not implemented |
| C06 App distribution | Signed Play Store/App Store apps, crash telemetry, accessibility test matrix, store rules and policy links | Flutter tests only; no signed production release |
| C07 Provider compliance | Official adapter contracts, supported APIs, permitted user scopes, vendor terms, independent live acceptance by provider | Some supported SDK/CLI adapters; independent sessions require consent and cannot be universally taken over |
| C08 Security review | External pentest, dependency/secret scanning, SBOM, threat model sign-off, data export, vulnerability disclosure | Threat model in development; outside assessment pending |
| C09 Operations | Uptime SLO, on-call runbooks, alerting, recovery-time/point objectives, load tests, retained encrypted backups | Partial scripts; real managed operations absent |
| C10 Commercial/legal | Company/entity setup, domain, TOS, privacy policy, data-processing terms, taxes, customer support and commercial Tailscale/hosting rights | Owner/business work at commercial launch stage |

**Do not use a Tailscale Personal plan to serve a commercial public SaaS without checking its current terms.** A free private pilot and a legal production customer network are separate decisions. Electricity, device operation, bandwidth, AI-provider usage and hosting can cost money even if software is open source.

## D. Explicit provider capability boundaries

- **Supported path:** O-AGENT-owned or explicitly connected coding agent sessions through officially installed/authenticated runtimes such as available Codex CLI, Copilot SDK and Claude Agent SDK, with owner review. Each provider's actual allowed scopes and plan still control what works.
- **Remote screen path:** a specifically installed, owner-consented companion can help control *visible desktop UI* in the private preview. That does **not** make it a provider-native session integration.
- **Not represented as implemented:** arbitrary existing ChatGPT Work browser approvals, any unrelated claude.ai website chat, private Cursor IDE chat panes, or an arbitrary consumer ChatGPT website project, where no supported authorization/control API is available. No hidden scraping or fake integration status.
- **Cost:** the product must not claim free inference merely because the local server or an SDK package is free.

## E. Release decision protocol

1. Protect the working `main` release; develop as a draft PR and review changes.
2. Pass SQLite/legacy, Flutter, Windows, PostgreSQL/RLS, MCP, API, web and private pilot Compose tests. Check the latest commit's jobs, **not** a prior successful run.
3. Inspect the GitHub workflow's real artifact outputs before requesting a single batched Android APK. Never trigger one after every small change.
4. Run B01–B08 once with the owner; record device/OS/browser versions, provider accounts tested (not credentials), outcomes and defects.
5. Keep public signup disabled until **all C gates have a verified owner and exit-test evidence**.
6. Mark a gate ready only with a reproducible test, bounded capability and explicit known limitations.

This document deliberately separates automated confidence from production certification. It is a roadmap and acceptance matrix, not a claim of a finished commercial launch.
