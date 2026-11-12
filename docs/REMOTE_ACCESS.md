# O-AGENT — Remote phone access without USB

The first real remote path uses **Tailscale Serve**, a private HTTPS connection to your *running laptop* through your own tailnet. This does not open a public port, rely on ADB, or require the phone to be near the laptop.

**Important:** This is an opt-in development setup. Your laptop must be awake and online. Cloud agent tasks may continue elsewhere, but their synchronization to this locally hosted control plane stops while the laptop is offline. A truly always-on O-AGENT needs a separate hosted control plane plus properly secured user identity and durable storage.

## One-time actions (Windows laptop and Android phone)

1. Install the official Tailscale desktop app from https://tailscale.com/download/windows. Sign in and authorize the laptop.
2. Install Tailscale on Android (from Google Play) and sign in to the **same tailnet**. Enable its VPN connection.
3. Double-click **O-AGENT.cmd** in your existing repository. Ensure the local dashboard works and the worker shows online.
4. Double-click **ENABLE-REMOTE-ACCESS.cmd** in the repository. Read the prompt and type YES to enable *private Tailscale Serve*, not Funnel.
5. Tailscale may request a one-time Windows Administrator prompt and permission to enable HTTPS certificates in the tailnet. Complete its official authorization flow.
6. Note the printed HTTPS URL, such as **https://your-laptop.your-tailnet.ts.net**. This is a personal example, not a working URL for another account.
7. Open O-AGENT on Android. Connect with that HTTPS URL and your existing **operator token**. On a personal phone, you can opt in to Remember this device. Avoid doing so on a shared device.
8. Disconnect the USB cable. Switch the phone to mobile data. Keep Tailscale connected and test the HTTPS URL's /health endpoint from the phone browser, then open O-AGENT and refresh Projects.

After one-time setup, start O-AGENT on Windows as usual. Tailscale Serve uses background mode; check its actual status with the Tailscale app if it does not reconnect.

## Security boundaries

- Tailscale Serve shares within your authenticated tailnet only. **Never use tailscale funnel** with the development control-plane bearer token.
- Keep the existing operator token private. Do not disable Android certificate validation.
- Tailnet access controls still apply; manage and revoke devices from Tailscale's admin console.
- The backend stays bound to localhost 127.0.0.1:8787.
- The worker continues using authenticated outbound polling and remains read-only for the current supported machine tools.
- A revoked/expired Tailscale device cannot connect unless reauthorized. Existing O-AGENT development tokens should still be rotated before wider deployment.
- This does **not** give remote access to ChatGPT Work's managed cloud browser, live laptop screenshots, or unrelated provider permissions.

## Troubleshooting

If ENABLE-REMOTE-ACCESS.cmd fails:
- Ensure Tailscale is installed and authenticated on Windows.
- Enable HTTPS certificates/MagicDNS in your tailnet if prompted.
- On Windows, Tailscale Serve may require an Administrator terminal. Run the documented Tailscale command **tailscale serve --bg 8787** from Windows Terminal (Admin) after O-AGENT is running.
- Verify **tailscale serve status** reports a private HTTPS URL.
- Verify Tailscale is active on Android and both devices appear in the same tailnet.
- The app endpoint must be HTTPS and the URL origin only (no paths or query strings).
- If /health succeeds but API login fails, the **operator token** in O-AGENT does not match the backend.

To disable remote Serve: run **tailscale serve --https=443 off** from an authorized Windows shell.

## Future fully hosted control plane

Always-on remote O-AGENT needs a managed hosting account, an actual signed-in provider connection and a separately secured runtime:
- Hosted HTTPS API behind individual user sessions, revocable device credentials and appropriate network controls.
- PostgreSQL for persistent projects, jobs, messages, events, approvals, identities and revocations.
- Object storage for screenshots, documents and provider artifacts.
- Hosted provider adapters and a durable worker/job queue.
- On-prem Windows worker as outbound client only; cloud workers for workloads able to run independently of the personal laptop.

**This cloud deployment has not been authorized or provisioned yet.** Do not assume the existence of a cloud server or billing account. For project architecture see UNIFIED_AI_WORKSPACES.md.

Official docs: https://tailscale.com/docs/reference/tailscale-cli/serve and https://tailscale.com/docs/install/android
