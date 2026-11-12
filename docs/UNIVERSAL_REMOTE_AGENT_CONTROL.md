# Universal AI Remote Control: research and implementation contract

## Product requirement

O-AGENT must be a **remote controller of real external AI sessions**, not only a repository/project list: select a session, send a prompt and supported attachments, inspect actual tool/agent output, answer permission requests, and operate over an authenticated no-USB phone link. Browser/screen viewing is a separate capability requiring its own authorized display source.

## Provider capability truth table (official interfaces checked 12 Nov 2026)

| AI system | Supported adapter direction | What must NOT be falsely claimed |
| --- | --- | --- |
| Codex CLI/IDE | Official Codex app-server JSON-RPC: thread/list, thread/resume, turn/start, live item and turn notifications, server-initiated approvals | Does NOT remotely click another active terminal's text box or mirror its window |
| Codex Cloud | Official Codex CLI cloud list; create a NEW task with cloud exec | No arbitrary ChatGPT Work/browser remote control and no existing Work project sync |
| ChatGPT Projects/Work | ChatGPT own web/mobile UI; ChatGPT Apps SDK/custom MCP server can let ChatGPT intentionally invoke tools on an external system | No verified generic third-party API to enumerate existing ChatGPT Project chats, type into any chat, replay UI clicks or capture the managed Work cloud browser |
| OpenAI Responses API | New/O-AGENT-owned API conversations, tool calls, file/image inputs and streaming | Different state from existing consumer ChatGPT conversations |
| Claude SDK/Managed Agents | App-owned documented session IDs, events, tools and consented permission callbacks | Not equivalent to controlling arbitrary claude.ai consumer browser tab |
| Gemini API/Live API | O-AGENT-owned sessions, function calls, streaming, optional Files API media inputs | Not a universal control protocol for existing Gemini consumer chats |
| Local Windows/Chrome | Future enrolled, explicitly user-consented window capture/remote input | No hidden screen capture, cookie extraction or third-party provider-managed cloud browser mirroring |

Official sources:
- https://learn.chatgpt.com/docs/app-server
- https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md
- https://help.openai.com/en/articles/10169521-projects-in-chatgpt
- https://help.openai.com/en/articles/12515353-building-with-the-apps-sdk
- https://developers.openai.com/api/docs/guides/custom-mcp-server
- https://platform.claude.com/docs/en/managed-agents/events-and-streaming
- https://code.claude.com/docs/en/agent-sdk/overview
- https://ai.google.dev/gemini-api/docs/live-api/tools
- https://ai.google.dev/gemini-api/docs/files

## This release: supervised Codex CLI / IDE turns

1. Select a **genuine saved Codex CLI session** on the Android Projects screen.
2. Open **Codex control and live activity**, enter a prompt and select Read-only (default) or Project edits.
3. O-AGENT checks the selected saved session ID against the signed-in worker, real project folder and a fresh metadata sync.
4. Submit the full prompt and mode for **explicit operator approval**; no work runs until approved.
5. The laptop worker opens the official app-server with the existing Windows Codex account, resumes the selected thread, and starts the authorized turn.
6. Read-only requests use a documented restricted read-only sandbox. Project-edits requests use a documented workspace-write sandbox with the selected folder as writable root and network access disabled. The backend rejects read-only permission escalations.
7. Incoming actual agent message deltas, tool activity and turn completion are persisted in a bounded task log and shown on Android every 3 seconds while the live view is open.
8. Any supported in-flight command/file permission escalation is presented on the phone, tied to the original task and expires after 3 minutes. It is denied automatically unless the user explicitly approves. Unknown requests fail closed.
9. Completed results reflect the actual provider completion status; a missing model, unsupported sandbox or inaccessible existing Codex session is a failure, not a fake result.

Safety: this is NOT UI automation on ChatGPT's consumer website. Resuming a session owned by another active CLI process may fail; that must be surfaced rather than secretly taking control. The current backend uses local JSON with development bearer tokens, so never expose it to the public internet. The existing private Tailscale Serve configuration can continue to provide no-USB access while the laptop is online.

Verification status: integration and protocol tests can prove the code path using a mocked Codex process; they cannot verify the user's real Codex account/model access until the owner tests a live session.

## What remains to build

- **Attachments:** authenticated encrypted storage, content-type and size validation, image/PDF/document picker, provider-specific file ingestion, retention and deletion.
- **Provider expansion:** a real app-owned Claude SDK / managed-agent connector and Gemini API connector, with distinct API authorization and per-provider feature manifests.
- **ChatGPT companion:** optional ChatGPT custom MCP app which lets ChatGPT explicitly call O-AGENT tools when the account supports it; this cannot reverse-read every existing ChatGPT conversation or mirror Work.
- **Screen viewing:** signed user-session Windows agent with explicit consent indicator and restricted local browser/window WebRTC feed; no hidden capture.
- **Hosted service:** production auth/identity, external account links, durable PostgreSQL, attachment object store, SSE event cursor, push notifications, cancellation and resume. A hosted cloud setup requires a user-authorized deployment and credentials, not hard-coded secrets.
- **Real-account validation:** test on the owner's signed-in Codex CLI, check one read-only prompt, approve a project edit, deny a tool escalation, verify results survive phone reconnection, and confirm no USB is needed.

### Definition of done

Never label a feature complete because the APK builds. Require the actual provider connection, real tool output, authenticated action authority, error handling and restart/reconnection tests.
