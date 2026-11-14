# O-AGENT commercial handoff: exact boundaries and owner-only inputs
**Stage: private pilot and incremental source engineering. NOT a published commercial app.**

## What the repository can deliver now
- Personal Tailnet-only SaaS pilot: PostgreSQL, Keycloak OIDC, Caddy, signed worker and secure HTTPS mobile PWA.
- Owner approval, deny, audit, export, recovery, encrypted backup, worker enrollment.
- Development branch adds team workspace foundation: individual private home workspaces, explicit workspace selection, owner/operator/viewer roles, hashed one-time 15-minute team invitations, member revocation, server-side role enforcement, FORCE RLS, real PostgreSQL isolation/replay tests.
- New dashboard team page and native Flutter **external-browser SaaS entry**. Flutter has **not** embedded a production OIDC login, and the existing APK is still the previous preview.
- Actual tenant-scoped run usage. Billing is **disabled**; there is no provider checkout, fabricated invoice, inferred token usage or active paid subscription.
- Existing official provider SDK/CLI connections require real authenticated provider sessions on enrolled dedicated workers.

## Owner inputs — only during one final acceptance/deployment stage
**Never send any credential, signing key, session cookie or private .env file into GitHub issues, PRs, chat messages or screenshots.**

1. A computer you control with Node.js 22.12+, Docker and Tailscale, and an Android/iOS phone in the same Tailnet for first private-pilot acceptance.
2. Sign in to your official supported AI-provider CLI/SDK accounts locally and choose one test workspace. Do not expect access to arbitrary preexisting browser tabs. Obtain explicit provider authorization when their interfaces require it.
3. For public rollout only: a domain, an eligible paid/commercial hosting account, database, OIDC issuer and secret manager. The owner must choose jurisdiction and spending limits.
4. For payment activation only: a legally eligible payment provider merchant account, verified server-side webhook credentials, pricing/currency/tax/refund decisions and terms. **Do not accept payment until signed events, durable ledgers and recovery have been independently exercised.**
5. For signed Android distribution only: an owner-controlled signing identity/keystore, application ID and store or private release decision. Never put signing credentials in source or CI logs.
6. For launch only: real physical-device, provider, multi-tenant security, cloud recovery, billing, privacy/legal and independent penetration-testing acceptance.

## Why universal ChatGPT/Claude/Cursor website takeover is not claimed
Third-party websites and IDEs do not expose one universal secure API for replaying the existing user's exact authenticated screen, approvals, prompts and clicks. O-AGENT can interact with supported first-party SDKs/CLIs and authenticated, consented local workers. Browser DOM automation and cookie extraction are **not** equivalent to official supported session continuation; never silently impersonate browser sessions or bypass provider permissions.

## How to test the newest available functionality without a new APK
1. Clone or download the **feature branch**, not `main`. On Windows double-click `START-O-AGENT.cmd`, inspect diagnostics and keep the computer awake.
2. Join the same private Tailscale network on your phone and open the HTTPS origin printed by the starter. Sign into Keycloak, change the temporary password and enable MFA.
3. Install the mobile PWA on the phone home screen and double-click `CONNECT-O-AGENT-WORKER.cmd` to select a trusted project folder and approve the verified worker.
4. In the web dashboard, use **Team & workspaces** to generate a short-lived viewer/operator invitation; another OIDC login redeems it and selects the shared workspace. Verify cross-tenant permission denial and member revocation.
5. Verify mobile approval, explicit denial, device reconnection, interrupted task recovery and actual file diffs with your selected provider. Do not assume green CI replaces a physical test.
6. Use the **Plan and usage** panel only for truthful run records. It does not activate payments.

## Release guardrails
- Do not merge PR #32 automatically, trigger an Android [mobile-release] build on every small commit or overwrite an existing signed APK.
- Never expose the private pilot through Tailscale Funnel or unrestricted router port forwarding.
- Do not label this system production-safe until live infrastructure, roles, per-tenant worker isolation, real payment integration, signed mobile release, monitoring and independent security review pass.
- The above list is the remaining real owner contribution bundle; source-level engineering and automated testing are not owner-only tasks.
