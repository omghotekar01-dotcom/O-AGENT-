# O-AGENT — original requirements and acceptance tracker
Updated: 2026-11-15 · Scope: iOS + Android native Flutter and Windows private worker

## The original promise
O-AGENT is NOT another prompt form or chatbot. It is the user's one-stop PHONE control center for real ongoing AI work on a personally authorized laptop or separately authorized provider-managed agent. It must show truthful running sessions, live output/screens, prompt input, approvals for actual actions, and resulting project changes. The same app must serve Android and iOS.

## User acceptance journey (never substitute a placeholder)
1. Install mobile app; login to a private account. Main screen shows online PCs, real agent sessions, active jobs, and pending decisions. No separate old/new O-AGENT login screen.
2. Start PC with **one** double-click `START-O-AGENT.cmd` after first-time installation. It checks Docker/private server/identity and signed worker, and restores the PREVIOUSLY CONFIGURED Windows remote gateway when local owner credentials already exist.
3. Select a real Codex/Claude/Copilot SDK conversation or a visibly shared Windows desktop. Distinguish real owned SDK threads from consumer website chats.
4. See message history, file changes, progress and permissions; send next prompt. An owner's read-only Send runs without redundant self-approval. Workspace-writing or tool changes still need meaningful exact approval.
5. The phone remotely views an authorized Windows display (with consent), uses visible trusted input helper, and opens GitHub, Cursor and VS Code project features in the same app navigation.
6. If PC/provider is offline, explain the blocked step; no fake agent responses, fabricated sessions, unsafe account import or hidden remote capture.
7. Resume the same work after app/background/network reconnect. iOS/Android app releases and real physical tests must pass before claiming commercial readiness.

## Features and delivery gates
| Priority | Required feature | Current branch status | To mark fully DONE |
|---|---|---|---|
| P0 | iOS-style UI on Android and iOS | **Implemented code, not device-accepted**: native Cupertino navigation, original light dashboard components, card contrast fix | Physical Android + iPhone screenshots, accessibility, OS dark/light tests |
| P0 | One native app, not a second welcome page | **Implemented navigation**: current app now mounts older `RemoteMissionControlScreen` under Remote | Migrate previous gateway authentication to current OIDC; confirm login flow on user devices |
| P0 | Real live Windows desktop | **Existing old gateway feature now accessible from Remote** with explicit owner permission | Verify capture, frames, input, Tailscale HTTPS, Windows helper and stop/revoke on real laptop |
| P0 | One double-click Windows startup | **Implemented, automated checks**: `START-O-AGENT.cmd` also launches old screen gateway if prior local secure config exists | Run with actual Windows, Docker, Tailscale, first/next boot; establish old gateway HTTPS without manual extra scripts |
| P0 | Agent inventory: Codex, Claude, Copilot, ChatGPT, Gemini, Cursor, GitHub, VS Code | **Implemented truthful directory and routing**: unsupported consumer chats routed to consented Remote, not fake APIs | Provider-specific verified authentication and session status on physical phone |
| P0 | Prompt and live agent work | **Implemented for verified Codex local threads and O-AGENT-owned Claude/Copilot SDK**; owner read-only goes to real run details | Real provider account tests, streaming latency, failure/retry, read-only sandbox verification |
| P0 | Actual approvals only | **Backend policy changed; CI-tested**: no second owner approval for read-only provider turn; write/tool requests still require approvals | Physical phone approval/denial on real file/command requests, independent authorization audit |
| P0 | VS Code files & live changes | **Older authorized companion exists**, reachable via Remote | End-to-end scoped files/diffs/unsaved filename tests and consolidated account authorization |
| P0 | GitHub projects/Actions/PRs | **Older authenticated project connector exists**, exposed from integrated Remote | New account token/OAuth connection UI, secure unified authorization and live test |
| P0 | Cursor Cloud Agents | **Older connector exists**, accessible from Remote | Provider key connection, list real cloud agents, follow-up/steer acceptance test |
| P1 | Existing ChatGPT/Claude/Gemini website chat **screen** | **Possible only through user-consented Windows screen sharing and trusted remote input**; no account-chat import | Real screen/input test with each user-authorized app and clear permission indicator |
| P1 | Existing ChatGPT/Claude/Gemini website **session API** | **Not implemented / not promised**: no verified general third-party consumer-chat takeover API | Documented provider capability + authorized integration, otherwise retain screen-only control |
| P1 | Attach screenshots, PDFs, documents from phone | **Not verified end-to-end** | Privacy-protected file picker, size/type checks, supported provider adapter, actual artifact acceptance |
| P1 | In-app keys/connection setup for each user | **Incomplete**; old gateway uses Windows DPAPI and newer private pilot uses OIDC | User vault, per-provider OAuth/BYOK, revocation, least-privilege validation and recoverable errors |
| P1 | Reliable notifications, reconnect and resume | **Partial existing event/worker infrastructure** | Android/iOS real-device end-to-end push, offline test, expiry and event replay |
| P2 | Hosted SaaS and phone store releases | **Private pilot only** | Isolated cloud workers, Apple signing/TestFlight, Android release signing, real QA, independent security review |

## Architecture policy
- **A signed-in SaaS worker is not the same as the old owner-token remote screen gateway.** They now share one mobile navigation but not credential authority. This is a migration blocker; NEVER silently copy DPAPI secrets or weaken auth to work around it.
- The native app must display what the verified provider/worker actually reported. Owner, worker, folder, session, request ID and action digest stay bound at every step. Do not invent progress or claim every third-party browser tab was imported.
- "Prompt" is a user request, not a tool permission. Read-only authorizations may queue directly only after backend verification of the real **workspace owner** and trusted worker; writes/tool permission escalations are audited and require exact decisions.
- Consumer ChatGPT/Claude/Gemini apps: an explicit remote desktop is a legitimate user-visible control surface only with owner consent; it does NOT expose a provider session API.
- Never build repeated Android APKs for small commits. Run Flutter analyze/test + Windows + SaaS security checks, then ONE consolidated debug APK. iOS signing remains independent.

## User-observable release test
1. Phone Agents screen uses **readable** light text/surfaces even with Android OS dark appearance, searchable list and compact scroll.
2. Tapping **Open live PC screen**, **VS Code**, **ChatGPT web screen**, **GitHub**, **Cursor** stays inside the new app Remote navigation; no "Earlier preview backend" welcome screen.
3. Once the previously authorized gateway is connected, Remote shows existing real project files/runs and permits live screen view/control only with physically consented capture and helper.
4. No verified SDK sessions -> Sessions explains exact missing adapter. It never asks for meaningless workspace-inventory "AI" prompts.
5. Real signed-in owner sends read-only Codex/SDK prompt -> backend queues one run, phone opens actual events and confirmed result, with no duplicate approval. A non-owner or write request still needs a separate approval, and a revoked/offline worker cannot run.
6. Reconnect, stop, revoke, deny and interrupted-run recovery are observable and cannot silently replay side-effecting work.
7. Same UX works on physical iPhone and Android. No release readiness claim until tested.

## Verified official reference points
- Codex App Server thread/turn lifecycle, live events, steering and action approvals: https://learn.chatgpt.com/docs/app-server
- Claude Code remote control (existing CLI sessions are accessible through Claude account/mobile surfaces, not a generic third-party takeover): https://code.claude.com/docs/en/remote-control
- Cursor Cloud Agents v1 durable agents and follow-up/steer API: https://prod.cursor.com/docs/cloud-agent/api/endpoints
