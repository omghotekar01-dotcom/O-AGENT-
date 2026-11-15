# Native O-AGENT mission control

The primary Android and iOS screen is Flutter-native, not a browser command center.
The earlier legacy operator-token project screens remain available inside the app.

Keycloak uses the OS system browser ONLY for OAuth PKCE sign-in and redirects
to com.omiiii.oagent:/oauth2redirect. Normal work and approvals use native APIs.
The dedicated oagent-mobile public client is registered by the Windows starter.
Refresh credentials are encrypted with OS secure storage; access tokens stay in memory.

Native Home, Work, Inbox, Devices and Activity call real signed-in SaaS endpoints.
Work creates supervised requests; Inbox requires a separate hash-bound decision.
Provider capabilities are shown only when enabled on the enrolled worker.

Unsupported arbitrary ChatGPT website takeover and screen streaming are not claimed.
The laptop worker must remain on and reachable through Tailscale.
Real Codex CLI session turns require a verified native provider session ID.

Physical acceptance requires a batched new APK, secure login, heartbeat,
read-only workspace inventory, exact approval, and genuine result verification.
No APK is generated on ordinary code commits.
