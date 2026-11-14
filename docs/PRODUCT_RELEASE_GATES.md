# O-AGENT market-readiness gates — 2026-11-14

This file describes the **actual state** of the software, not a marketing
claim. A successful CI check or debug APK is **not** equivalent to a
deployable multi-customer service. Do not advertise consumer AI session
takeover or unattended computer control.

## Product positioning

O-AGENT is a workspace control system that can show verified machine,
project, task, approval and selected coding-tool status. It can operate
a trusted local VS Code workspace via an explicitly installed companion,
with owner permission and temporary edit grants. Other provider runtimes
require distinct official connections and authentication.

## Delivered in the 0.9 release candidate

- Accessible mobile and web project file browser for enrolled VS Code folders.
- Read allowed text files; edit with hash-based optimistic concurrency;
  create new text files; rename within the same folder; request Trash with
  an additional local confirmation.
- Web workspace navigation for Overview, Project files, Activity & approvals,
  Connected tools, and Guided setup. All statuses derive from actual
  API responses; no fabricated counts.
- Read-only Git/unsaved change list from local VS Code extension, optional
  screened Windows remote pointer and input pairing from the previous release.
- Official provider adapter status matrix for Codex CLI/Cloud, GitHub,
  Anthropic, Gemini, OpenAI, Copilot SDK, Claude SDK and Cursor.
  A configured credential is NOT proof of an active session.
- No source content persisted to task database by the file relay; file
  request/results expire from server memory after 90 seconds.

## Product limitations that require separate, real integrations

| Provider | Existing supported bridge | Not automatically accessible |
| --- | --- | --- |
| VS Code | Trusted workspace companion: Git status, file read/CRUD, approved open | Existing Copilot Chat transcript, arbitrary editor terminals and every VS Code extension approval |
| Codex CLI / IDE | Saved local workspace metadata, approved SDK/CLI turns with applicable provider access | Arbitrary currently running independent CLI window |
| Codex Cloud | Synced task metadata and authenticated new task requests with approval | Live ChatGPT Work browser or user’s private ChatGPT Projects |
| GitHub | Verified repository/workflow/PR metadata | Existing Copilot Chat session content or GitHub-hosted UI without an authorized remote session bridge |
| Copilot SDK | Supervised tasks using an installed authenticated SDK runtime | Existing consumer IDE sessions by default; SDK remote session support requires individual enrollment |
| Claude Agent SDK | Supervised turns using an authenticated runtime | Existing claude.ai conversations or unconsented terminal sessions |
| OpenAI / Anthropic / Gemini | O-AGENT-owned API conversations with customer-provided valid keys and quota | Private consumer website chat histories |
| Cursor Cloud | Separate official API key with provider-supported agent runs | Live local Cursor IDE tab control by default |
| Grok, DeepSeek, Perplexity and other sites | Links may exist, but aren't integrations | Private consumer chats, controls, files and approvals without independently documented APIs |

Supporting docs: GitHub Copilot SDK remote sessions
https://docs.github.com/en/copilot/how-tos/copilot-sdk/features/remote-sessions
and VS Code remote agent sessions
https://code.visualstudio.com/docs/agents/run/remote-agent-sessions .
Use official provider consent only; do not scrape accounts or bypass quotas.

## BLOCKERS before a public multi-user launch

1. **Isolation:** the existing control plane and worker token are
   development-oriented; verify per-tenant data segregation and enforce
   per-user, per-device authorization for every worker, file and provider
   request. A global worker token is not acceptable for untrusted tenants.
2. **Auth & enrollment:** replace manually distributed worker/operator secrets
   with expiring, owner-approved device pairing and provider OAuth/SDK flows.
   Add recovery, revoke, account deletion, session expiry and re-auth.
3. **Managed backend:** deploy monitored private HTTPS, scalable queues and
   durable work coordination. The current Windows localhost backend plus
   memory-only session previews is not an always-on hosted service.
4. **Privacy & security:** independent threat model, audit of remote input and
   source relay, malware and dependency scanning, tests for permission
   escalation, logging policy, safe redaction and secret detection, abuse
   limits, device enrollment protection and incident response plan.
5. **Provider contracts:** verify terms, SDK/API permissions, quota reporting,
   account identity, error recovery and exact session scope for each
   integration. Do not claim cross-vendor consumer-session mirroring.
6. **Mobile distribution:** release signing, Play Store compliance, supported
   Android versions, crash reporting, accessibility testing, onboarding,
   privacy policy, terms and account deletion handling. CI's debug APK is
   for testing, not a commercial release artifact.
7. **Acceptance tests:** real Windows/Android/E2E tests for disconnect,
   offline conditions, stale file version, large Unicode, symlinks, document
   unsaved conflicts, destructive confirms, error states, and all approved
   provider runtimes. CI syntax/unit tests are necessary but insufficient.
8. **Operations and commercial readiness:** customer support and billing,
   usage/cost visibility, backups and restoration, data retention, monitoring,
   SLAs, multi-region policy and platform legal review.

**Launch gate:** only call the product market-ready once each blocker has
a documented owner, an automated or manual acceptance test, and a verified
pass against production-like infrastructure. Until then describe it as an
experimental private preview.

## One bundled test release, not repeated builds

Make code changes together in a feature branch. Run backend, VS Code, Flutter
and Windows checks on the branch. Only after those checks pass, create one
batched Android debug APK + VSIX to test on the owner's actual devices.
No production mobile store deployment or unattended permission escalation.
