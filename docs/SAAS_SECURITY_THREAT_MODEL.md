# O-AGENT SaaS security threat model (private pilot → customer launch)

**Trust boundaries:** Browser ↔ Tailscale private HTTPS ↔ local Caddy gateway ↔ Node API ↔ PostgreSQL tenant context; owner OIDC identity ↔ action approval; signing-key worker ↔ leased provider runtime ↔ workspace filesystem and vendor account.

| Threat | Existing control | Remaining verification or mitigation |
| --- | --- | --- |
| Token forgery or confused OAuth client | OIDC JWT algorithm/issuer/audience/client/scope validation; authorization-code PKCE; in-memory access token | Real account browser login/MFA, logout, key rotation, IdP outage behavior |
| Wrong user accesses another workspace | Transaction-local tenant ID from verified OIDC subject, PostgreSQL FORCE RLS, automated cross-tenant tests | Independent penetration test, separate team/role design for commercial release |
| Stolen/replayed worker request | Device-owned Ed25519 signature over method/path/body/timestamp/nonce; database replay uniqueness | Platform secure enclave/DPAPI key storage, key rotation, real offline/revocation tests |
| Pairing impersonation | Short-lived 256-bit pairing token, one-time owner-confirmed public key fingerprint | Social engineering review, trust onboarding UX, phishing-resistant passkeys/MFA |
| Hidden tool authorization | Exact action hash, one-time owner approval, lease, tool-specific decision with expiry | Vendor callback semantics and native SDK permission-level acceptance |
| Hostname spoofing or accidental public exposure | Exact expected HTTPS Host/Origin, local-only Docker bind, Tailscale Serve not Funnel | Actual firewall/router/Tailnet ACL verification, commercial deployment proxy hardening |
| Provider data leaks in notifications | Generic lock-screen payload with no filenames/prompts/tokens; restricted push endpoint hosts | Browser push permission acceptance, account-switch cleanup, notification privacy settings |
| Worker escapes project folder | Realpath checks, per-worker workspace root and restricted advertised capability | Real symlink/ACL tests, OS sandboxing, executable/egress restrictions for production workers |
| Provider crash/lease expiration | Signed lease renewal, abort on failure, no silent replay of side-effecting turns | Kill-process recovery drill, partial filesystem edits, idempotent vendor operations |
| Device revoked during execution | New signed calls rejected; queued work cancelled, active runs moved to explicit recovery | Physical test: long-running subprocess stops on authorization failure, resource cleanup |
| Unbounded consumption/DoS | Per-owner run quotas, pending caps, bounded events/results, pairing limits | Public edge rate limits, CAPTCHA/signup control, model token/spend budgets, CDN/WAF |
| DB schema drift | Forward-only versioned checksum migration and advisory lock | Real upgrade from preserved old pilot volume, encrypted pre-migration backup and restore |
| Lost/damaged laptop | AES-256-GCM encrypted DB backup and authenticated pre-restore validation | Off-device secure storage, proven restoration with chosen RPO/RTO, user training |
| Deleted user's data persists elsewhere | Server-side tenant erasure revokes server-side keys; physical files/provider accounts/backups excluded | Retention/deletion policy for off-server copies, backup lifecycle, legal compliance |
| Supply-chain vulnerability | Direct npm dependency versions and CI tests | Locked transitive dependencies, SBOM, pinned container digests, SCA review |
| Forged local build status | CI SHA/PR check evidence; draft PR until owner acceptance | Signed release artifacts, provenance/SLSA controls and independent reproducible builds |

**Non-goals:** bypassing vendor restrictions, sharing customer provider credentials between tenants, remotely approving high-risk actions without the owner's authenticated consent, or advertising private consumer chat takeover as a native integration.

**Residual risk:** personal home hardware can be stolen, disconnected, malware infected or asleep; self-hosted Tailscale access is not proof of an always-on commercial backend. Device signing keys are stored as local files, and a malicious administrator of that host can read them. Full native sandbox and platform key storage are unimplemented.

**Privacy handling:** never include access tokens, Keycloak credentials, private keys, SQL passwords or account details in CI logs. Preserve only bounded audit action metadata. Provide user-controlled erasure of control-plane data; distinguish it from deletion in providers, local project files and encrypted backup copies.
