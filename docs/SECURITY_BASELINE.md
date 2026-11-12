# Security baseline

This is an engineering baseline, not a certification claim. Use OWASP ASVS 5.0.0 for backend/web verification, OWASP MASVS + MASTG for Android verification, OWASP GenAI Top 10 for agent-specific risks, NIST SP 800-207 for Zero Trust, NIST SP 800-218 for secure development, and IETF RFC 9700 for OAuth security. Run independent security review before a public production launch.

## Identity and devices

- OAuth/OIDC authorization-code flow with PKCE S256, exact redirect URI matching, state/nonce validation and secure session rotation.
- Prefer passkeys where the identity provider supports them. Require step-up authentication for sensitive credential, device, approval and destructive-operation changes.
- Register each Android device and Windows worker with a distinct cryptographic identity. Support immediate device/session revocation.
- Android private keys are generated/stored in Android Keystore and remain non-exportable where supported. Inspect hardware-backed security level; do not assume StrongBox exists on every device.
- Use short-lived access tokens and rotate refresh credentials. Use DPoP or mTLS sender-constrained credentials where the issuer and client support them; neither replaces authorization.
- Revalidate device/session state on sensitive backend actions. A cached JWT claim alone is not sufficient for immediate revocation.

## Transport and network

- TLS 1.3 for external APIs where supported; reject invalid certificates and use modern TLS configuration.
- Worker control uses authenticated outbound mTLS or short-lived device-bound tokens over WSS. No public inbound SSH/RDP port by default.
- WebRTC media uses DTLS-SRTP; signaling is separately authenticated and authorized. TURN credentials are short-lived.
- Network location is never treated as identity. Apply per-resource authorization, egress restrictions and explicit service identities.
- Block cloud metadata endpoints and private-network ranges from arbitrary agent/browser/tool egress unless a narrowly scoped allowlist explicitly requires them.

## Credentials and cryptography

- Provider API keys and refresh tokens are encrypted immediately on receipt using envelope encryption backed by a managed KMS/HSM; use per-secret data-encryption keys and key versioning.
- Never return decrypted secrets to mobile/web clients after save. Show metadata, last four characters where safe, expiry/rotation status and revoke controls.
- Never place secrets in source control, mobile builds, prompts, agent context, URLs, stdout/stderr, screenshots, application logs, traces or analytics.
- Redact authorization headers, cookies, passwords, OTPs, private keys, recovery codes and sensitive clipboard data before persistence.
- Use established cryptographic libraries and platform key stores. Do not invent a custom encryption algorithm or custom key exchange.

## Authorization and approvals

- Default deny. Scope every permission to workspace, project, agent, run, device, connector, tool, target and operation.
- Enforce policies on the server immediately before side effects. UI visibility is not an authorization boundary.
- Approval records bind the exact action, canonical argument hash, target, risk class, run/session, requester, approver, expiry and one-time nonce.
- If target or arguments change, approval becomes invalid and must be requested again.
- Require approval for destructive file/branch operations, deploy/publish, external messages, purchases/financial actions, permission changes, new network destinations and secret access.
- Use least-privilege GitHub installation permissions and narrowly scoped OAuth grants. Never use an unrestricted personal token as the default connection strategy.

## Agent-specific threats

- Treat webpages, emails, documents, repository files, terminal output, screenshots and tool responses as untrusted data. They cannot override system policy or user approvals.
- Separate instruction channels from retrieved content. Tool schemas validate arguments; server policy decides whether the action is permitted.
- Run untrusted code in an isolated workspace with resource limits, filesystem boundaries and network egress policy.
- Apply per-run max duration, step count, token/cost budget, retry budget and concurrency quota.
- Include cancellation, pause, emergency stop, lease expiry and worker revocation.
- Prevent duplicate side effects using idempotency keys and action-specific deduplication.
- Detect suspicious tool loops, repeated permission denials and unexpected privilege/network escalation.

## Audit and privacy

Record who/what/when/where for meaningful actions: actor, workspace, project, agent, run, provider session, worker/device, action, target, canonical argument hash, policy result, approval reference, timestamps, result code and artifact references. Store bounded/redacted details; do not persist secrets merely to make logs “complete”.

Use append-only permissions for event tables and export audit evidence to storage with retention controls. Hash chaining alone is not sufficient if a privileged administrator can rewrite both the records and the chain. Define retention, deletion, legal hold and export rules.

## Release-blocking security tests

- Cross-workspace and cross-user IDOR attempts.
- RLS policy bypass, exposed view and privileged-function review.
- Secret leakage in app bundle, network payload, logs, traces, artifacts and crash reports.
- Expired/revoked access token and device revocation behavior.
- Replay, duplicate command, stale fencing token and approval-argument mismatch.
- Prompt injection in web page, file, issue, email and screenshot content.
- Sandbox escape attempts and blocked network destinations.
- Unauthorized remote input, session takeover and stale WebRTC control.
- Android local storage, backup, screenshot and clipboard privacy.
- Worker disconnect, reconnect, stolen device key and kill-switch behavior.
- Backup restore and audit export integrity.

## Standards and references

- OWASP ASVS: https://owasp.org/www-project-application-security-verification-standard/
- OWASP MASVS / MASTG: https://mas.owasp.org/
- OWASP GenAI Security Project: https://genai.owasp.org/
- NIST SP 800-207: https://csrc.nist.gov/pubs/sp/800/207/final
- NIST SP 800-218: https://csrc.nist.gov/pubs/sp/800/218/final
- OAuth 2.0 Security BCP (RFC 9700): https://www.rfc-editor.org/rfc/rfc9700
- DPoP (RFC 9449): https://www.rfc-editor.org/rfc/rfc9449
- Android Keystore: https://developer.android.com/privacy-and-security/keystore
- WebRTC Security Architecture (RFC 8827): https://www.rfc-editor.org/rfc/rfc8827
