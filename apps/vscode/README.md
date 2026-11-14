# O-AGENT VS Code Companion

An opt-in extension for tracking Git/unsaved files, browsing a real
source tree, viewing supported source text, and saving reviewed edits
to a trusted Visual Studio **Code** workspace. File content flows only
through an expiring, owner-only in-memory request relay; it is not persisted
in the task database. This is **not** a Copilot chat takeover or screen
control extension.

## Install in VS Code (not Visual Studio)

Do not double-click the `.vsix`: on Windows that may open the unrelated
**Visual Studio 2022/2026 VSIX Installer** and fail.

Download and extract the latest `o-agent-vscode-companion-vsix` artifact.
Then either:
- In VS Code, open **Extensions** (`Ctrl+Shift+X`), select **... → Install from VSIX...**
  and select `o-agent-vscode-companion.vsix`; or
- In your updated O-AGENT project folder, run `INSTALL-VSCODE-COMPANION.cmd`.
  It invokes the Visual Studio Code command-line installer.

## Recommended: connect from the O-AGENT sidebar (no keys to paste)

1. On your trusted Windows laptop start **O-AGENT.cmd** once. Use the
   same Windows account that originally configured O-AGENT.
2. Open your exact project folder in VS Code. Install the new
   **O-AGENT Workspace Companion 0.5.0** VSIX and open the **O-AGENT** icon
   in the VS Code activity bar (left sidebar).
3. Click **1 · Connect using Windows setup**. Review the modal and select
   **Connect this laptop**. The extension decrypts the saved WORKER token
   using the Windows account's existing DPAPI protection; it never prints
   the token and stores it in VS Code SecretStorage.
4. Confirm the **exact project folder** when prompted. The status changes
   to **Connected**. The sidebar now provides **Allow edits for 30 minutes**
   and **Stop sharing now** without requiring the Command Palette.

Automatic import is intentionally restricted to VS Code **on the same
Windows machine and same Windows user account**. Remote VS Code extension
hosts and other operating systems must use the manual HTTPS path below.
It does not take over Copilot Chat or other private provider sessions.

## Manual or remote connection (advanced)

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

The extension sends a short list of Git changed paths and unsaved
file names to the private backend every five seconds. When the owner
deliberately opens **Remote → VS Code live file changes → Browse project
files**, it can also browse folders and read allowed text files. The
contents are held only temporarily in server memory and are never
persisted in task history.

To enable remote saving of edited text, you MUST locally run
**O-AGENT: Enable Mobile File Editing (30 minutes)** from VS Code's
Command Palette and confirm its modal. Each phone edit requires a
separate **Review & save** confirmation and succeeds only if the
file still matches the hash originally read and has no unsaved local
edits. This permission expires after 30 minutes or when the companion
stops. Source reads are capped at 48,000 characters and protected /
hidden, binary and linked files cannot be edited.

The new mobile and web file browser can also **create** an empty text file,
**rename** an existing text file inside its current folder (without
overwriting an existing destination), and request **Move to Trash** after
both phone/web and local VS Code confirmation. The file has to match its
original hash; hidden files, credential paths and symlinks are rejected.
The separate 30-minute local permission covers these operations too.

The legacy **Remote file navigation** form only requests opening a
specific file in the local VS Code window. It still requires owner
approval and a second local confirmation; it is not the file editor.

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
