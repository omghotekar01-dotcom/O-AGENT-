# O-AGENT VS Code Companion

An opt-in extension for tracking changed/unsaved filenames and approved file opens
in a trusted Visual Studio **Code** workspace. This is **not** a Copilot chat
takeover or a screen-control extension.

## Install in VS Code (not Visual Studio)

Do not double-click the `.vsix`: on Windows that may open the unrelated
**Visual Studio 2022/2026 VSIX Installer** and fail.

Download and extract the latest `o-agent-vscode-companion-vsix` artifact.
Then either:
- In VS Code, open **Extensions** (`Ctrl+Shift+X`), select **... → Install from VSIX...**
  and select `o-agent-vscode-companion.vsix`; or
- In your updated O-AGENT project folder, run `INSTALL-VSCODE-COMPANION.cmd`.
  It invokes the Visual Studio Code command-line installer.

## Configure on the same laptop as O-AGENT

1. Start `O-AGENT.cmd` and verify `http://127.0.0.1:8787/health` responds
   with the O-AGENT service information. If the launcher uses another port,
   substitute that port.
2. Open and **trust** a real project folder in VS Code.
3. Press `Ctrl+Shift+P`, choose **O-AGENT: Configure Secure Companion**.
4. For **Backend URL**, enter `http://127.0.0.1:8787` if VS Code is
   running on the **same** laptop as the backend.
   If VS Code is on a different device, use your private HTTPS Tailscale
   backend origin (e.g. `https://your-device.your-tailnet.ts.net`).
   Plain HTTP is **never** allowed for other devices, LAN addresses or domains.
5. For **Worker token**, use the existing Windows **WORKER** token saved
   encrypted under `%LOCALAPPDATA%\OAgent\settings.json`. This is **not**
   your phone OPERATOR token, GitHub token or AI API key. Never paste it into
   chat or issue trackers. The extension stores the token in VS Code SecretStorage.
6. Press `Ctrl+Shift+P` → **O-AGENT: Start Remote Workspace Companion** →
   **Enable**. The status bar should show `O-AGENT: connected`.

The extension sends only a short list of Git changed paths and unsaved
file names to the private backend. It does not upload file contents or diffs.
The owner phone can open **Remote → VS Code live file changes** to inspect
the feed. Opening a specific file requires owner approval **and** a second
confirmation in the local VS Code window.

## If connection fails

- **Cannot reach backend:** Start/restart `O-AGENT.cmd`; check
  `http://127.0.0.1:8787/health` in your laptop browser.
- **HTTP 401:** Wrong token. Reconfigure using the **WORKER** token rather
  than the **OPERATOR** token.
- **HTTP 404:** Server may be outdated or the URL does not point to your
  O-AGENT backend. Update/restart Windows server.
- **HTTPS DNS/certificate issues:** When VS Code and backend are on the
  same Windows laptop, use `http://127.0.0.1:8787` instead.
- **No changed files:** Open and trust the project folder; edit a file.
  Wait for the companion's five-second polling interval.
- **O-AGENT: disconnected:** Hover over status-bar text for a diagnostic.
  You may also run **Developer: Show Logs... → Extension Host** inside VS Code.
  Never include passwords or tokens in shared logs.

Run **O-AGENT: Stop Remote Workspace Companion** to stop the feed.
