# Connect external projects to O-AGENT on Windows

This is an optional **one-time configuration** on your own Windows user account. It does not transfer the GitHub/ChatGPT account connections used inside this ChatGPT conversation into O-AGENT automatically. A provider's authentication must happen in its own supported API/CLI.

## First: your actual Codex CLI / IDE workspaces (local sessions)

If `codex cloud list --json --limit 20` gives `{"tasks":[]}`, that only means no *Codex Cloud* tasks were returned. It does not tell us whether you have saved CLI/IDE coding sessions.

**To show the coding projects you work on through Codex CLI:**

1. Confirm `codex --version` and `codex login` have succeeded on your Windows account.
2. If you have never opened Codex in a project directory, go into your coding project folder in PowerShell and run `codex` to create a real saved session. `codex login` alone doesn't create projects.
3. Double-click `STOP-O-AGENT.cmd` and then `CONFIGURE-PROJECTS.cmd`.
4. Keep the existing GitHub project list and any Codex Cloud setting. Answer **Y** to **Sync MY local Codex CLI / IDE projects?** (a separate consent from Codex Cloud sync).
5. Restart `O-AGENT.cmd`; on Android open **Projects → Codex CLI / IDE** and refresh.
6. Tap a workspace to see the actual saved session titles, last updates and last-observed app-server state. Session metadata may be stale if the worker cannot sync.

See the full [Codex CLI workspace guide](CODEX_LOCAL_WORKSPACES.md) for privacy, limitations and recovery. These workspaces are not imported from GitHub account choices; they belong to the locally signed-in Codex CLI user. ChatGPT Work's managed chats are still a separate, unsupported surface.

## Part 1 — Public GitHub projects: immediate real data

The one-click launcher includes your O-AGENT repository in the default public GitHub list. After updating and restarting the backend, open the Android app **Projects** tab. You should see O-AGENT and recent actual GitHub Actions workflows, or a genuine API error if GitHub cannot be reached.

To add more repositories:
1. Stop the one-click backend using **STOP-O-AGENT.cmd**.
2. Open the repository folder and double-click **CONFIGURE-PROJECTS.cmd**.
3. Enter the GitHub repository IDs as a comma-separated list, for example: omghotekar01-dotcom/O-AGENT-,your-org/another-repo.
4. For private repositories, provide a **fine-grained GitHub token restricted to read-only repository metadata, Actions and Pull Requests**. This token is protected for the current Windows account with DPAPI. Public repositories need no token.
5. Choose whether to enable Codex Cloud task metadata. Restart O-AGENT by double-clicking its shortcut.
6. Open **Projects** and refresh. GitHub project details show actual status and links to the GitHub provider.

This integration does not control GitHub Copilot coding-agent sessions; it only reads GitHub repository/Action/PR endpoints supported by the official GitHub REST API.

## Part 2 — Existing Codex Cloud tasks (explicit opt-in)

Codex Cloud task list access works through the official Codex command-line client. It uses **the Codex account that is signed in on this Windows machine**, which may have eligibility/plan restrictions.

1. Install Codex CLI using its official instructions from https://developers.openai.com/codex/cli/ and review https://learn.chatgpt.com/docs/cli/reference.
2. Run the **one-time CLI login** in your own terminal: codex login. Authenticate using the provider's official flow. Do not share browser cookies, passwords, or session files with O-AGENT.
3. Check that the official CLI can list tasks: codex cloud list --json --limit 20.
4. Stop the launcher, open **CONFIGURE-PROJECTS.cmd**, and explicitly opt in to Codex Cloud task sync. Restart O-AGENT.
5. The worker reads up to 20 real Codex cloud task titles/status/URLs about every 45 seconds and publishes only that metadata to the authenticated O-AGENT backend.
6. Refresh Android **Projects**. Tap a Codex Cloud task to inspect its last reported state and open its original provider page. If the laptop has not synced for two minutes, the app marks the data **stale**.

Codex Cloud runs on the provider, but this local task-list bridge still needs your laptop online to refresh. Existing ChatGPT **Work** projects and its managed browser do not appear through this CLI.

## Part 3 — Submit a NEW Codex Cloud task from the phone

This is a write action and must be approved:

1. Make sure the laptop O-AGENT gateway and signed-in Codex CLI are online.
2. From Android **Projects**, open an imported Codex Cloud task, then select **Request new Codex Cloud task**.
3. Enter the target Codex Cloud **environment ID** (shown by your account's Codex task metadata) and your prompt.
4. Optionally select **Improve with AI** to propose a rewritten prompt. Review/edit the result carefully. This requires a working, billable OpenAI/Anthropic backend API account. A rate-limit/credit error does not silently dispatch anything.
5. Tap **Request approval**. The backend saves the complete, immutable environment and prompt but does NOT send it to Codex yet.
6. Return to **Approvals** and inspect the exact destination, prompt, target worker and impact. Tap Approve or Deny.
7. Only after approval does the worker run the supported CLI equivalent: codex cloud exec --env ENV_ID QUERY. O-AGENT records the actual submission command result.
8. Refresh **Projects** after the next Codex sync to find the provider's subsequent task status. A successful submission does NOT imply that cloud work completed.

**Important:** This is **not** a reply to an existing Codex conversation or ChatGPT Work chat. It creates a new Codex Cloud task. The external provider may require available credits or a configured Codex cloud environment.

## Part 4 — Use O-AGENT without USB

See [REMOTE_ACCESS.md](REMOTE_ACCESS.md). Tailscale Serve provides a private HTTPS URL to the running laptop, and Android can use that URL over cellular data.

## What isn't integrated yet

- Pre-existing ChatGPT Work conversations, cloud browser screen and Work approvals.
- Provider-managed browser screenshots, interactive remote control and live video.
- File/image/PDF attachments routed from O-AGENT to independent existing sessions.
- Full cloud-hosted O-AGENT availability while your own laptop is offline.
- Other cloud coding services without a verified provider connector.

See [UNIFIED_AI_WORKSPACES.md](UNIFIED_AI_WORKSPACES.md) for the full acceptance checklist and architecture.

## Security and troubleshooting

- Provider accounts and tokens must be authorized separately; no manual sharing of cookies, MFA codes, account passwords or unknown browser automation is supported.
- Never post fine-grained GitHub tokens, operator tokens or AI-provider API keys in chat, source code or screenshots.
- Logs: %LOCALAPPDATA%\OAgent\logs, development state: repository .local/oagent-data.json.
- The backend currently uses broad static development operator/worker credentials and unencrypted conversation state. Do not expose this development server to the public Internet.
- A webhook, model quota error, failed CLI login or unavailable cloud environment should be shown as a real failure, not a fabricated success.
