# O-AGENT: Mobile Accounts, Bring-Your-Own-Key and Batched App Releases

## What this milestone actually gives you

O-AGENT now has a **private per-user AI account mode**. A workspace owner can invite a person without sharing the owner operator token. The person connects to the same trusted HTTPS O-AGENT backend with a one-time invitation, receives a separate long-lived personal token, and manages their **own** OpenAI, Claude/Anthropic and/or Gemini API keys from the Android/iOS app. Their model settings and chat history are separate from the owner's and other members'.

**This is not yet a public SaaS sign-up or an always-on cloud instance.** The owner is still running a development backend on their laptop. Tailscale access requires that the invited phone be permitted on the same trusted private tailnet and the Windows laptop remain online. Public hosted OAuth, database tenancy and cloud workers are separate work.

## Install or update once

1. On Windows stop the launcher, pull latest main and restart `O-AGENT.cmd`. The launcher generates a fresh 32-byte AES-256-GCM vault key on the first run of this release, encrypts it using the current Windows user's DPAPI and saves the encrypted value under `%LOCALAPPDATA%\OAgent\settings.json`. **It does not reset your existing operator/worker tokens.**
2. On the Android phone, install the newly built **batched release** APK (produced only after the release marker commit). Your previously remembered operator connection should still work if the signing identity remains compatible.
3. On the phone, tap the top-right **settings** icon → **My AI accounts & invitations**.
4. Go to **Connections**. Tap a provider → enter the **model ID** and **your personal API key** in the hidden field → **Save securely**. Tap **Test** to make a genuine, potentially billable provider request. A provider that has not successfully answered stays unverified.
5. Open **Chat** to use that specific connected API key in a personal conversation. You can keep multiple provider keys saved and switch between them without restarting O-AGENT or entering secrets into PowerShell.

## Invite another person

1. On the owner's phone, open **My AI accounts & invitations** → **Account** → **Generate one-time invitation**. Copy the code privately; it expires in 15 minutes and can only be redeemed once.
2. Share the backend HTTPS URL and the invitation code via a trusted channel. Your existing private URL is `https://om-v16.tailbb6a8f.ts.net`. **Never share your operator or worker token.** Make sure the person can access the host via an explicitly authorized Tailscale connection.
3. The other person installs O-AGENT, chooses **Join with invitation**, enters the backend URL, their preferred display name and the one-time code. For a private personal phone, they can opt into **Remember this device** (Android Keystore/iOS Keychain).
4. They see **My AI workspace** with **Chat / Connections / Account**. They enter their own API key(s) and choose models. They **do not** receive the owner's project feed, Codex sessions, machine worker, task approvals or machine APIs.
5. To revoke them, the owner opens **Account → Invited members → Revoke access**. The user's token stops working and their encrypted provider settings and account conversation records are removed from the active local backend state.

## Required credentials and where users get them

| Function | User supplies | Where to enter |
|---|---|---|
| Owner O-AGENT connection | Existing operator token from original Windows setup | Original owner login screen (once if remembered) |
| New invited member | One-time 15-minute invitation code from owner | **Join with invitation** screen |
| OpenAI API-owned conversations | API key from https://platform.openai.com/api-keys and usable API credits | **My AI workspace → Connections → OpenAI API** |
| Claude API-owned conversations | API key from https://console.anthropic.com/ and applicable billing | **Connections → Claude API** |
| Gemini API-owned conversations | API key from https://aistudio.google.com/apikey and quota | **Connections → Google Gemini API** |
| Codex CLI session control on owner's laptop | Existing signed-in `codex` CLI and opt-in local connector | Owner **Projects → Codex CLI / IDE** (existing flow) |
| Shared private remote network | Tailscale permission for owner's Windows host and invited device | Tailscale applications, not an AI key field |

**ChatGPT subscriptions are not automatically OpenAI API balances**. Similarly, Claude and Gemini consumer subscriptions may be separate from developer API billing.

API keys are sent only via authenticated HTTPS to the user's chosen O-AGENT backend. The backend stores them as AES-256-GCM authenticated ciphertext with per-user/provider associated data. The 32-byte master key is held under the Windows user's DPAPI account protection, not in GitHub or the Android APK. Backend memory necessarily decrypts the selected key when calling that provider. Personal chat texts are currently stored in local JSON **without encryption**: do not use this development backend as a public multi-tenant production service.

**Important backup warning:** The DPAPI-protected vault master key is essential to decrypt users' API keys. Losing the Windows profile/settings backup can make existing encrypted keys unrecoverable. Do not reset it casually; do not send the encrypted settings file to other users.

## GitHub Actions cost/limit policy

**Ordinary pull requests and app edits:** run `flutter analyze` and `flutter test` only. No Android APK; no iOS simulator package.

**Release APK:** one explicitly marked final commit on `main` with `[mobile-release]` in the commit message triggers a single Android debug APK build, after the Flutter checks succeed. It does not automatically build iOS.

**Manual release:** In GitHub → Actions → **Flutter Mobile — Test & Build** → Run workflow. You can optionally enable the iOS simulator build. Only do this for consolidated releases, not every tiny UI fix.

Keep backend Node and Windows integration tests automatic. Automated checks do consume small GitHub Actions time but are far cheaper than repeatedly compiling Android and iOS native apps.

## What's not ready

- Open registration, password reset, SSO/OAuth, payment subscription, online laptop-independent cloud hosting, production-grade migrations/retention/tenant billing.
- Sending a personal user's BYOK model output into the owner's real machine tools. Machine control is intentionally separated from personal chats.
- Uploading files/images/PDFs from the mobile app to provider API sessions; these need a secure provider-specific input implementation and file storage policy.
- Live browser/screen capture and controlling arbitrary ChatGPT/Claude/Cursor/Copilot consumer tabs.
- Full session-control integrations for Claude Code SDK, GitHub Copilot SDK, Cursor and VS Code.

All are separate, consented engineering milestones and must never appear as connected without real account verification.
