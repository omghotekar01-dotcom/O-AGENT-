# O-AGENT — Multi-provider connection roadmap and honest setup

Updated: 12 November 2026.

## Working model

O-AGENT is an **agent control center** with projects, verified provider sessions, prompts, permission decisions, actual output streams, optional attachments, browser display where consented, and private remote networking. The user should not need to manually recreate existing Codex sessions.

**A real integration requires both supported provider capabilities AND permission from the user in that provider.** A user saying "full access" in conversation cannot make an unsupported consumer chat API appear or authorize third-party accounts automatically.

## Provider matrix

| Surface | Existing release capability | Exact next setup or implementation |
|---|---|---|
| **Codex CLI / IDE** | Authenticated read-only saved session discovery, approved Codex session turn, real events, tool approvals | Installed `codex`, logged into the same Windows account, local sync enabled in CONFIGURE-PROJECTS.cmd. Update both worker and mobile APK. Codex 0.167.2 sandbox fix in this release. Test on the owner's account. |
| **Codex Cloud** | Authenticated CLI task listing and approval-gated creation of NEW task | Cloud tasks/environment must exist on provider; this does not control ChatGPT Work projects. |
| **GitHub** | Actual workflow runs and PRs for explicitly configured repos | Add each repository; private repos require separate fine-grained read-only token. |
| **OpenAI API** | O-AGENT-owned agent conversations, safe backend tool loop and prompt refinement | Add a funded OpenAI API key in Windows launcher. Existing ChatGPT website conversations remain separate. |
| **Claude API** | O-AGENT-owned Anthropic Messages API agent and safe backend tool loop | Add a valid Anthropic API key in Windows launcher. Existing Claude Code/claude.ai sessions remain separate. |
| **Gemini API** | O-AGENT-owned Gemini generateContent conversation + prompt improvement without machine tools | Choose option **4** in CONFIGURE-O-AGENT.cmd and securely enter Google AI Studio API key. This selects Gemini as the single active O-AGENT chat provider and does not import consumer Gemini chats. |
| **Claude Code / Agent SDK** | Explicit capability listing, no independent CLI session control yet | Build a signed-in enrolled local Claude Agent SDK runtime, session list/resume, streaming and tool permissions. Never silently capture claude.ai credentials. |
| **GitHub Copilot SDK** | Explicit capability listing, no SDK-hosted agent session yet | Implement the official Copilot SDK session runtime and authenticated permission handlers. GitHub repository access alone is not Copilot agent access. |
| **Cursor CLI** | Explicit capability listing, no direct existing IDE agent control yet | Integrate the official Cursor Agent CLI with safe execution policy, session IDs and streamed events; no blanket `--force` approvals. |
| **VS Code** | Explicit capability listing, no IDE extension installed yet | Build and install an authorized VS Code extension that exposes exact open workspace/editor/agent capabilities, with visible per-window consent. |
| **ChatGPT Projects / Work website** | Clearly marked unsupported | No verified universal third-party API to inject messages into arbitrary existing ChatGPT chats, click all screen controls, or mirror the managed cloud browser. An optional ChatGPT Apps SDK/MCP companion can give ChatGPT actions that explicitly connect to O-AGENT, but not reverse-read existing chats. |
| **Remote laptop browser** | No live screen capture yet | Build a separately consented visible Windows screen-share bridge with window selection, privacy masking, WebRTC, one-time approvals and revocation. It must not silently observe the desktop. |
| **Always-on cloud** | Private Tailscale Serve to **online laptop** | Requires user's hosting/billing account, cloud OAuth/account identity, durable DB, audited secrets storage, queues and isolated cloud workers. Not provisioned. |

Official reference links:
- Codex app-server: https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md
- Current Codex sandbox protocol: https://github.com/openai/codex/blob/main/codex-rs/app-server-protocol/src/protocol/v2/permissions.rs
- Gemini API: https://ai.google.dev/api/generate-content
- Gemini CLI stream JSON: https://geminicli.com/docs/cli/headless/
- Claude Agent SDK: https://platform.claude.com/docs/en/agent-sdk/overview
- GitHub Copilot SDK: https://docs.github.com/en/copilot/get-started/sdk-quickstart
- Cursor Agent CLI: https://docs.cursor.com/en/cli/overview
- VS Code LM tool extension API: https://code.visualstudio.com/api/extension-guides/ai/tools
- ChatGPT Apps SDK: https://help.openai.com/en/articles/12515353-building-with-the-apps-sdk
- Tailscale Serve: https://tailscale.com/docs/features/tailscale-serve

## Installation order for this update

1. **Do not reset existing passwords or operator/worker tokens.** Keep Tailscale serving your existing private HTTPS origin.
2. On Windows, STOP-O-AGENT.cmd, then `git pull origin main` after this PR merges, then O-AGENT.cmd.
3. On Android install the new artifact `o-agent-flutter-android-debug-apk` over the existing app, preserving its Keystore token if the signatures match.
4. In Projects, open the same existing local Codex session that failed with `readOnly.access is no longer supported`. Tap **Reuse prompt for new attempt**, inspect Read-only, submit and approve a **new turn**. The previous failed task is retained as historical evidence; it is not retried automatically.
5. Observe the actual Codex text stream and result. If a different provider error appears, share that error (not any tokens) to guide compatibility work.
6. Optional Gemini API: `CONFIGURE-O-AGENT.cmd` is a full credential reconfiguration and requires re-entering your **existing** operator and worker tokens. Do not use it casually. Choose option 4 Gemini, set a model supported by your Google AI Studio key and restart. This changes the active **O-AGENT-owned chat provider**, NOT Codex CLI login.
7. For other tools, follow the official provider's login/SDK setup when their actual O-AGENT adapter ships. Merely clicking an unconfigured source does not connect it.

## Non-negotiable test gates

- Integration tests must catch protocol changes, 429 quota, unauthorized worker task, unsupported permissions and retries.
- Every rendered progress event must originate in a provider/worker response.
- Provider authenticity/connection status remains *unverified* until an actual authorized request succeeds.
- Production file attachments require size/type validation, secure storage with deletion, bounded input, an official provider transport, and privacy review. They are NOT present in this build.
- Screen view must have visible user consent, no raw cookie/password collection and no implicit control of ChatGPT's managed browser.
- CI tests plus APK do not imply real owner account/phone live verification or independent 24/7 cloud operation.

**This is a substantial incremental build, not 100% of the requested full universal product.**
