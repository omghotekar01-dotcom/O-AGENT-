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

## Consolidated native Android pilot build

- Flutter 0.13.0+15 restores a native-first mobile interface.
- Native PKCE login uses the registered `oagent-mobile` Keycloak public client.
- Home/Work/Inbox/Devices/More and run activity render in Flutter.
- Laptop enrollment, fingerprint approval and revocation are inside Flutter.
- The previous native operator-token workspace remains accessible separately.
- The Android debug APK must still be tested on a real phone after installation.
- Background native SaaS push notifications, arbitrary AI website takeover and
  unsupported live editor/tab synchronization are not represented as complete.
- The previous Android APK remains a separate older version and will still
  use its original browser handoff until replaced.
