# Cloud and public accounts (development candidate)

This branch adds email/password public member accounts with **verified email**, recovery,
scrypt password hashing, 30-day opaque revocable bearer sessions, rate-limited anonymous
routes, and a Docker/Render deployment recipe. Public members have **no machine-tool
privileges** and are isolated from all other members' keys and threads.

## Infrastructure you must supply

1. Deploy this repository as a **Render Blueprint** using render.yaml and a persistent disk.
   This is a starter single-instance deployment, **not** highly available or production-certified.
2. Set OAGENT_VAULT_KEY_BASE64 to a **new random 32-byte key** encoded as base64 in
   Render's environment secrets. Back it up in your own trusted secret manager.
   **Never** put the value into git, a client APK, a chat, or an email. Rotating it
   without re-encrypting stored keys will permanently invalidate the vault.
3. Configure a verified sender domain at Resend, set OAGENT_RESEND_API_KEY and
   OAGENT_MAIL_FROM (for example noreply@your-verified-domain.example) as private
   server settings. Set OAGENT_PUBLIC_URL to your deployed **HTTPS origin**, e.g.
   https://your-application.onrender.com. Without all settings, public signup
   deliberately remains disabled.
4. The cloud server also requires separate OAGENT_API_TOKEN and OAGENT_WORKER_TOKEN
   secrets for the legacy owner/worker paths. The Blueprint generates both; save them
   securely if you need your owner and desktop worker to connect.
5. Deploy the backend and create and verify a regular account using the in-app
   **Create account / Verify email / Sign in / Forgot password** forms.
6. Each member separately connects their own OpenAI/Claude/Gemini keys in Connections.

**Privacy:** The JSON data file is on a persistent disk, not encrypted in full.
Passwords are salted/hashed and provider keys encrypted. Conversation text, email
addresses, and audit metadata are not yet encrypted at rest. Configure Render network
controls, backups, logging redaction and monitoring before exposing real user data.
The persisted JSON storage is single-process only; do not run multiple replicas.
There is no independent cloud coding worker in this deployment: existing laptop
Codex CLI sessions remain available only while the enrolled laptop worker is online.

**Not part of these APIs:** ChatGPT/Claude/Cursor website-session takeover,
agent UI screen sharing, arbitrary remote shell access or unapproved write actions.

## Latest test-release hardening

- Personal AI chat and provider verification use longer mobile request timeouts to match provider network latency.
- A failed GitHub repository lookup no longer prevents provider/chat data from loading in the account screen.
- Unauthenticated invitation redemption is rate limited per network address.
- Public signup stays disabled unless the backend also has an initialized vault key, and single-server public registration is capped at 500 accounts to protect the JSON development store.
- Model defaults were refreshed, but actual model access remains provider- and account-specific; use the in-app **Test** action after entering your key.

This release is for private staging and app verification, not security-certified public SaaS hosting.
