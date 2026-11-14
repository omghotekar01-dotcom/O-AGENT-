# O-AGENT SaaS staging deployment candidate

**Status: deployable source and staging reference, NOT a running commercial service.** This backend is separate from the Windows localhost O-AGENT preview. Creating configuration does not provision a domain, database, identity provider, paid infrastructure, or AI-provider accounts.

## Infrastructure

Use managed PostgreSQL 16 with TLS hostname verification, encrypted backups, and a separate SQL migration identity. The runtime database identity must not be a superuser, table owner, or BYPASSRLS role. The application checks forced row-level security at startup. The migration identity is only supplied to a short-lived migration job, never the public API container.

Use an OIDC provider with exact issuer, JWKS, API audience, registered OAuth client IDs, and oagent:read / oagent:operate scopes. A browser public client must support authorization-code PKCE S256 and allow its trusted origin to exchange the code for access tokens. For initial setup configure the documented variables in deploy/saas/api.env.example through a secret manager.

Build the API: docker build -f deploy/saas/Dockerfile.api -t oagent/saas-api:staging .

Build a per-tenant worker: docker build -f deploy/saas/Dockerfile.worker -t oagent/tenant-worker:staging .

The staging compose file deploy/saas/compose.staging.yaml binds the API to localhost only. A separately configured HTTPS reverse proxy with preserved Host is required. Do not publish a database port or expose worker private keys. A tenant worker must be deployed in a dedicated sandbox with its own provider account, workspace, egress restrictions, resource limits, and identity.

## Setup sequence

1. Provision and separately authenticate a trusted OIDC issuer, a HTTPS domain and managed PostgreSQL. Keep all passwords, CA certificates and provider keys out of GitHub and mobile bundles.
2. With a separate migration role, set the OAGENT_MIGRATION_DATABASE_URL secret and run the migration command inside an isolated job. Review the SQL and grants before allowing users.
3. Configure the OIDC issuer's registered redirect URI to https://YOUR_HOST/ and client authentication for a PKCE public SPA. Put the exact issuer, JWKS and audience in API environment secrets.
4. Start the API behind HTTPS. Verify /health/ready and a real signed-in /v1/me response. HTTP health alone never proves a valid provider account or SaaS launch.
5. On a dedicated customer-owned machine or per-tenant sandbox, install the signed worker package and run node apps/saas-worker/src/enroll.mjs with the SaaS origin. It creates a device-owned Ed25519 signing key. The owner opens the shown pairing link in the authenticated O-AGENT dashboard, checks the key fingerprint and approves the exact device.
6. The original worker receives its assigned device identity automatically, then starts with node apps/saas-worker/src/worker.mjs. Never share a worker process or provider credentials across separate tenants.
7. Enable only official provider runtimes that are installed and genuinely authenticated. First test a disposable project in read-only mode. O-AGENT will require a separate owner decision for every run and a separate tool permission for supported write operations.
8. Test action hashes, revocation, approval expiry, slow provider responses, network loss, tenant cross-access, lost leases and recovery on real devices and managed cloud infrastructure.

## Implemented engineering protections

- PostgreSQL forced RLS for tenant-owned devices, runs, approvals, event history and audit records; one tenant for each verified OIDC user identity in v1.
- Device-owned Ed25519 keys, method/path/body/timestamp/nonce request signatures, replay nonce database, explicit revocation, and owner fingerprint confirmation.
- Real persistent run state, idempotency keys, approval-bound action digest, time-limited leases and bounded append-only progress event records.
- Scoped official MCP v2 tools that read only the authenticated owner's data, and only request (never directly approve) a new supervised run.
- An OAuth PKCE web interface displaying genuine device status, approvals and native agent runs, with no fake backend counts or automatic approvals.

## Unfinished production gates

Live IdP/provider verification, cloud provisioning, tenant-team membership/roles, production secret vault/KMS, independently reviewed SQL privileges, signed device-key platform storage, cloud execution egress sandboxing, vulnerability scanning and locked dependency manifests, full telemetry, backups and restore drills, signed mobile apps, billing/quotas, privacy/legal compliance, abuse monitoring, user deletion and third-party security review remain mandatory. Browser/service automated tests are not a substitute for actual provider or device acceptance. The legacy render.yaml is not an acceptable public multi-tenant SaaS deployment.

Provider website session takeovers are still limited by official integration scopes: no universal control of arbitrary ChatGPT Work, Claude web, or local Cursor IDE tabs is implied.

**Do not open paid public customer signup until these gates have documented real-world passes.**

## Database upgrades and release safety

The migration runner now records SHA-256 checksums in `schema_migrations`, takes a transaction-scoped PostgreSQL advisory lock, applies migrations exactly once, and refuses to continue if an applied migration file was edited. Existing personal pilots receive an idempotent forward-only workspace-root/push-subscription compatibility upgrade. **Back up first**; running this migrator is an operational database change, not a substitute for a restore drill. Never change the contents of a numbered migration after rollout; write a new numbered file instead.
