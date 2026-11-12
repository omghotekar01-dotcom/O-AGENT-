# O-AGENT: set up once, then double-click (Windows)

This starts the **real development control plane** and laptop worker, verifies the machine is online, and sets up the Android USB bridge if ADB and an authorized phone are connected. No repeated PowerShell commands, tokens or terminal windows are needed.

## One-time setup on your Windows laptop

1. Install [Node.js 22+](https://nodejs.org/) if necessary.
2. In your existing O-AGENT repository (for example, `C:\Users\ASUS\OneDrive\Desktop\O Agent\O-AGENT-`), run **`git pull origin main`** once to retrieve this update.
3. **Close the two OLD terminal sessions** where you previously started `npm start` and `npm run worker`. The new launcher deliberately refuses to interfere with manually running servers.
4. Double-click **`O-AGENT.cmd`** in your repository. Its first launch asks for configuration just once:
   - Paste your **existing operator token** (the one already accepted by your Android app), or press Enter to generate a new one. If you generate a new operator token, enter that new token in the phone app once.
   - Paste your existing worker token or generate a new one.
   - Keep worker ID `my-laptop` and safe workspace `C:\Users\ASUS\OAGENT_TEST_WORKSPACE` unless you need something different.
   - Select an AI provider and enter its API key in the hidden prompt, or skip for machine-only operation.
5. After setup it starts the backend and gateway, checks actual online state, opens the local web dashboard, and creates an **O-AGENT shortcut on your Windows desktop**.

An AI key requires separate provider API access and billing; it cannot be supplied automatically by ChatGPT. A configured key is not a verified successful provider call.

## Every time after the first setup

- If using a real Android phone, plug it in with USB debugging enabled. Authorize the computer once on the phone.
- **Double-click O-AGENT on your desktop.** It restores the local credentials, reuses already-running launcher processes, and retries the USB bridge. No `npm start`, `npm run worker` or `adb reverse`.
- Open the Flutter Android app; connect to `http://127.0.0.1:8787` if not already connected. On your first mobile login, check **Remember this device** if the phone is private. Android Keystore/iOS Keychain then protects the operator token for automatic reconnects. **Disconnect** clears the stored token. Leave it off on shared phones.
- To shut down, double-click **`STOP-O-AGENT.cmd`** in the repo. The stop command checks process ownership before terminating them.

The launcher does not expose your backend to the internet. The server binds to localhost; the phone connects over authorized USB debugging.

## Credentials and logs

All files here are local and excluded from GitHub:

| File | Purpose |
|---|---|
| `%LOCALAPPDATA%\OAgent\settings.json` | Operator token, worker token, provider key protected using Windows DPAPI, per Windows account |
| `%LOCALAPPDATA%\OAgent\processes.json` | Backend and worker process IDs for safe stop/restart |
| `%LOCALAPPDATA%\OAgent\logs\` | Backend and worker logs |
| `.local\oagent-data.json` in the repository | Task and conversation history (**not encrypted**) |

**Do not share your operator token or model key.** Protect your Windows user account. Anyone with access to your unlocked account can run your local O-AGENT instance. DPAPI secrets do not migrate to another Windows account or computer automatically.

To update your saved provider key or tokens, stop O-AGENT and double-click **`CONFIGURE-O-AGENT.cmd`**. This is a deliberate reconfiguration and warns before overwriting existing credentials.

## Troubleshooting

| Problem | Solution |
|---|---|
| Port 8787 in use | Close old manual `npm start` session, then click launcher again |
| Old worker process detected | Close old manual `npm run worker` session, then click again |
| Node missing | Install Node.js 22+ and reopen the launcher |
| Gateway fails | Check `%LOCALAPPDATA%\OAgent\logs\worker.stderr.log` |
| No AI replies | Configure a valid AI provider key and test a chat; setup alone cannot verify provider authorization |
| Phone disconnected | Reconnect USB, authorize debugging and double-click O-AGENT again |
| ADB missing | Install Android Platform-Tools; backend and web still run |

PowerShell is run with `-ExecutionPolicy Bypass` **only for that launcher process**; it does not change machine-wide policy. Inspect the repository's local scripts before first use if Windows SmartScreen warns.

See [AI setup](AI_SETUP.md) for your model options and [MVP runbook](MVP_RUNBOOK.md) for backend technical details.
