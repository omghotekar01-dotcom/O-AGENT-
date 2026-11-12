# O-AGENT — Your actual Codex CLI / IDE projects

This is the missing part of the original product concept: **the projects you work on using the Codex terminal or IDE should appear in O-AGENT without being manually recreated as O-AGENT projects or GitHub repositories.**

## Two different Codex services

- **Codex CLI / IDE (local)**: persistent agent session history on your Windows user account, associated with the working directory of each coding project. The official \`codex app-server\` supports \`thread/list\`; O-AGENT reads this, groups sessions by cwd, and displays the genuine recent titles/updates. It does **not** need a Codex Cloud task.
- **Codex Cloud**: provider-hosted cloud tasks, listed via \`codex cloud list --json --limit 20\`. A legitimate empty result means there are no cloud tasks exposed to that signed-in account. It says nothing about local CLI/IDE history.
- **ChatGPT Work projects/conversations**: a different product surface. O-AGENT cannot claim to read its managed chats or browser; this connector does not transfer those sessions.

The O-AGENT mobile display shows saved sessions and last-updated times. **It does not prove a separate Codex process is active, mirror current browser screens, read the complete conversation, or send prompts into existing sessions.** Even a \`notLoaded\` session can still be active in a separate Codex app/CLI process.

## Do this once on the same Windows account where Codex is signed in

1. Ensure \`codex --version\` works. You already successfully installed Codex CLI and completed \`codex login\`.
2. If you have no existing local CLI sessions, open PowerShell in the project you want tracked, for example:
   
   ~~~powershell
   cd "C:\Users\ASUS\OneDrive\Desktop\O Agent\O-AGENT-"
   codex
   ~~~

   Use Codex normally to create a genuine project thread. A successful \`codex login\` alone does not create a coding session. Work started inside ChatGPT Work remains separate.
3. Double-click \`STOP-O-AGENT.cmd\` in the repo.
4. Double-click \`CONFIGURE-PROJECTS.cmd\`. Keep your GitHub repo list; you can keep Codex Cloud sync at the previous setting if desired.
5. At **"Sync MY local Codex CLI / IDE projects? [y/N]"** type **Y**. The consent screen explains what metadata is sent.
6. Double-click \`O-AGENT.cmd\`. It will start the backend and worker with local discovery enabled. The worker calls the official app-server \`thread/list\` from this same Windows user, then sends only the bounded session ID, short preview/title, working directory, last update, model provider and last observed app-server status to O-AGENT.
7. Keep your existing Tailscale connection running. On Android, open **Projects** and refresh. Check the **Codex CLI / IDE** source and filter. Tap a project to see the actual sessions grouped by working folder.

If no sessions appear, verify that you actually used \`codex\` within a project folder under the same Windows account. The Codex Cloud list can remain empty while local projects are present.

## What is shared and what stays private

**Sent to your own O-AGENT backend after explicit opt-in:** up to 80 recent session IDs; project folder paths (cwd); brief session previews/titles; update timestamps and metadata. The backend currently stores this data in local development JSON and can serve it to your authenticated mobile app over your private Tailscale connection.

**Never read by this connector:** \`auth.json\`, provider access tokens, passwords, browser cookies, full conversation transcripts, local project file contents or live screen frames. The app-server request is explicitly scoped to the currently signed-in Codex account where the history format supports it; some legacy sessions without creator IDs may still be included by the official Codex list implementation.

**Privacy warning:** Session previews or project folder names may contain confidential information. Do not enable this connector with private corporate projects unless you understand the current development backend's local JSON retention. Turn it off with CONFIGURE-PROJECTS.cmd and restart to stop future sync; existing stored snapshots may remain until purged from the local development state.

## Status semantics

- **Connected** source: app-server listing succeeded recently, even if it returned zero sessions.
- **Configured, unverified**: opted in but no successful recent local sync.
- **History available** project: O-AGENT has genuine saved Codex session metadata; not a live execution claim.
- **Stale** project: no successful sync for at least two minutes.
- **Not loaded** session: the scanner's fresh app-server doesn't own this session. This says nothing about the state of a separate running terminal/IDE process.

## Next feature milestones

1. Secure read-only Codex session transcript/event viewing with bounded data and per-project privacy options.
2. Explicit user-approved \`thread/resume\` + \`turn/start\` via an O-AGENT-owned persistent app-server process with authenticated event streaming and sandbox/approval handling. No background command injection into existing independent user apps.
3. Rich prompt/file composer and genuine provider-specific permissions.
4. Account identity + multiple Codex accounts with revocable linking; currently the local Windows OS/CLI login is the one source.
5. Always-on hosted O-AGENT so independent cloud providers can be supervised while the laptop is offline.

Official interface: https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md
