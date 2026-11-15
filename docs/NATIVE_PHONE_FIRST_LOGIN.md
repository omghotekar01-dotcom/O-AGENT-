# O-AGENT native Android — one-double-click private pilot

**Use one PC shortcut only:** `START-O-AGENT.cmd` from the repository root.
The same window starts the Docker private server, checks Tailscale HTTPS,
registers the Android OAuth client, shows the phone address, and starts the
laptop worker. It never overwrites existing private credentials, wipes Docker
volumes or exposes the server publicly.

## First use

1. **Prerequisites (one time):** Install Node.js 22.12+, Docker Desktop,
   and Tailscale on Windows. Install Tailscale on Android. Sign into the
   **same private Tailscale network** on both devices and enable MagicDNS
   and HTTPS certificates in tailnet settings. The launcher can open an
   installed Docker Desktop if its engine is not running, but it cannot
   consent to Tailscale login or install system software for you.
2. Pull the latest branch `feat/saas-secure-control-plane-20261114` into your
   **existing** O-AGENT repo. Do not replace a configured installation with
   an unrelated new folder.
3. **Double-click** `START-O-AGENT.cmd`. Use the same shortcut for all
   future starts. It reports actionable `[FIX]` messages when a requirement
   is missing. A failed readiness check **stops** worker enrollment.
4. The terminal displays **your real private HTTPS address**, e.g.
   `https://your-computer.your-tailnet.ts.net:8443/`. On your Android phone,
   open the existing O-AGENT APK and enter that exact origin under
   **Private HTTPS address**. Select "Remember this phone" only on a
   trusted device. Tap **Sign in to native app**.
5. First login is Keycloak user `pilot-owner`; its initial password is
   stored locally as `OAGENT_OWNER_PASSWORD` under
   `deploy/saas/free-pilot/.env.local` on **your own PC**. Change the
   password and enable MFA; on subsequent logins use the new password.
   Never share the file or any password.
6. On first startup, the **same** launcher window opens a single Windows
   project-folder picker. Choose an existing project folder you trust.
   O-AGENT saves this choice locally under
   `%LOCALAPPDATA%OAgent	rusted-workspace.txt` and reuses it on
   subsequent runs.
7. The PC displays a **one-time private pairing link** and a device
   fingerprint. After signing in on your phone, open **Devices →
   Enroll a new laptop**, paste the link, and approve it **only when the
   fingerprint matches** your own PC. The worker starts automatically
   after approval and resumes future sessions without repeated pairing.
8. Open **Work** on the phone; request a read-only inventory, review
   its action in **Inbox**, and verify the real response in task history.

Keep the Windows one-click console open and the laptop awake while you
want local AI work available remotely. Native login, personal-device trust,
and vendor agent sign-in are consent steps, **not safe to bypass**.

## If something goes wrong

- **No Docker or Tailscale:** Install/sign in to the prerequisite and
  run the same `START-O-AGENT.cmd` again. Do not use public Funnel.
- **`[FIX]` on launch:** Read that exact diagnostic and address the stated
  prerequisite; do not wipe/force-reset an existing installation.
- **Phone says "Secure operation failed":** First check your own
  private HTTPS origin with `/health/ready` in your phone browser.
  If unavailable, check both Tailscale connections, the Serve route and
  Docker readiness. If the health endpoint works, check mobile OAuth
  registration and browser login.
- **Worker already running:** A second one-click invocation detects the
  existing worker and does not start a duplicate.
- **Changed project folder:** Stop the current worker, then use the
  advanced `CONNECT-O-AGENT-WORKER.cmd` folder switch once, or remove
  only `%LOCALAPPDATA%OAgent	rusted-workspace.txt` to trigger
  a new folder picker on the next one-click start.
- **Provider sessions missing:** Vendor CLI/SDK installations and account
  login are separate; O-AGENT cannot take over arbitrary ChatGPT.com
  conversations where no supported integration exists.

## Safe Git pull (inside an existing repository)

```powershell
git status --short
git fetch origin
git switch feat/saas-secure-control-plane-20261114
git pull --ff-only origin feat/saas-secure-control-plane-20261114
```

If the branch does not exist locally, use
`git switch --track origin/feat/saas-secure-control-plane-20261114`
after fetch. If there are uncommitted changes or divergent commits, stop
and preserve them; do not use `git reset --hard`. If you cloned a
new repository for the first time, use:
```powershell
git clone --branch feat/saas-secure-control-plane-20261114 https://github.com/omghotekar01-dotcom/O-AGENT-.git
cd O-AGENT-
```

The single-click launcher does not require a new APK build.
