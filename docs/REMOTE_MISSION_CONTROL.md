# Remote mission control — development milestone

## Goal

The phone is the **supervisory console** for actual agent projects and tasks
on the user's laptop or on separately authorized cloud workers; it is not
another chatbot. A real agent adapter needs real account authorization,
owned-session IDs, streamed output, scoped permissions and durable state.

## Implemented in this branch

- Owner-only GET /api/remote/overview exposes only verified worker heartbeats,
  saved Codex CLI session metadata, actual supervised run state, last activity
  updates and pending per-action approval counts. No fake active IDE status.
- Remote tab → Remote agent mission control shows status and lets the owner
  open supervised Codex sessions, review exact approval requests and prompt
  a saved thread. Updates refresh every 3 seconds while open.
- Existing official Codex app-server adapter resumes a real saved thread in a
  separate supervised process, not via keyboard injection into an already-open
  terminal. All prompts require owner approval; supported file/command
  permission requests are deny-by-default and scoped to the active run.
- Persisted local Codex metadata now reloads on backend restart.
- Provider and GitHub credential dialogs keep text controllers alive through
  Flutter route teardown, with new widget tests for this crash class.

## Setup for current Windows + Tailscale owner

1. On your Windows account, install and sign in to official Codex CLI,
   confirm using codex --version, and create a real session by running codex
   inside an actual coding project folder.
2. Stop O-AGENT, double-click CONFIGURE-PROJECTS.cmd, answer Y to sync local
   Codex CLI/IDE sessions, then restart O-AGENT.cmd.
3. Ensure your private Tailscale Serve URL is working and the worker shows
   online. Do not expose development bearer tokens using Tailscale Funnel.
4. Android: Remote → Remote agent mission control → select a synced
   session → Prompt supervised Codex session.
5. Select read-only for a first test. Review the exact prompt, folder and
   mode. Tap Approve on the real request. Watch the activity timeline.
6. For project edits, explicitly select the write mode, inspect each real
   command/file approval and approve or deny. Unsupported permission escalation
   is denied automatically.
7. If another interactive Codex process owns the thread, Codex may refuse
   resume. It must display a failure rather than secretly taking over a tab.
8. Turning off the laptop stops local worker execution. This is not an
   independent cloud agent.

**No separate OpenAI API key is needed just to route a Codex CLI prompt**.
The CLI must still have its own supported account login and account access.
Personal AI Chat is a separate service. Grok/DeepSeek are not substitutes for
a session bridge; they are optional future inference providers.

## Provider connector matrix

| Agent | Current capability | What remains |
| --- | --- | --- |
| Codex CLI / IDE | Actual saved session list, supervised new turns, streamed text and tool events, approvals | Real-account and real-device validation; not same live IDE input box |
| Codex Cloud | Actual cloud task metadata and approval-gated NEW tasks | Full existing hosted-session control, richer official events |
| Claude Code / Agent SDK | Not implemented | Enrolled SDK runtime, real sessions, event and permission callback bridge |
| GitHub Copilot SDK | Not implemented | SDK authorization, session handles, authenticated event stream and approvals |
| Cursor Cloud Agents API | Not implemented | Account-scoped Cloud Agents API integration and permission/capability checks |
| Gemini API | O-AGENT-owned personal chat | Agent-runtime and tool session integration |
| Grok / DeepSeek API | Not implemented | Allowlisted provider-specific API adapter and independent user credentials |
| VS Code | Not implemented | Opt-in signed local extension or separately authorized remote desktop |
| Windows/browser screen view | Not implemented | Visibly consented screen/window source and encrypted WebRTC stream |
| ChatGPT website / Work | No verified general third-party session-takeover interface | Cannot claim control of arbitrary existing conversations or managed browser |

Official reference documentation:
https://learn.chatgpt.com/docs/app-server
https://learn.chatgpt.com/docs/codex-sdk
https://code.claude.com/docs/en/agent-sdk/overview
https://prod.cursor.com/docs/cloud-agent/api/endpoints

## Architecture and release gates

Use authenticated phone → private Tailscale HTTPS → owner-only O-AGENT backend
→ outbound worker polling → consented local agent runtime. Keep project/session
identity exact; do not mistake an observed saved session for a running browser.
The backend owns the action log and approval state, not LLM output text.

Never silently capture unrelated windows, browser cookies or provider auth.
An independently installed Windows companion must display a visible capture
indicator and let the user choose and stop the shared window. Its media
transport must enforce short-lived viewing permissions, end-to-end encryption,
and explicit session revocation. This is a separate later milestone.

Pass Node tests, Flutter analysis and tests, Windows integration, then live
real-agent and physical-device approval/denial/reconnect tests before any
release. Production additionally needs durable DB, authenticated event
streaming and cloud deployment security review. Avoid repeated APK builds.
