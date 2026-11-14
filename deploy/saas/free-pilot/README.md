# Free, private O-AGENT pilot
**Not a public SaaS launch.** Your computer runs PostgreSQL, Keycloak, Caddy and the API; it must stay on, and model-provider usage can still cost money.

Install Docker Desktop or compatible Compose and Tailscale on the computer, and Tailscale on your phone. Sign into the same private tailnet on both; enable MagicDNS and HTTPS certificates in Tailnet settings.

```sh
cd deploy/saas/free-pilot
node setup.mjs
docker compose --env-file .env.local -f compose.yaml up -d --build
tailscale serve --bg 8791
```

Run `node doctor.mjs` for eight explicit connection checks, then `tailscale serve status` and open the private HTTPS URL on your phone. **Do not use Tailscale Funnel**, router port forwarding, or a public domain for this personal pilot.

The first import creates a private `pilot-owner` login with a randomly generated temporary password in your local `.env.local` (`OAGENT_OWNER_PASSWORD`). Sign in as `pilot-owner` using the dashboard and change the password when prompted. Enable MFA from Keycloak's account console. If needed, administer additional users at `https://YOUR-TAILNET-HOST/auth/admin/` with the separate `admin` and `OAGENT_KEYCLOAK_ADMIN_PASSWORD` credentials. No fixed/default password is embedded in GitHub.

Then open the O-AGENT home dashboard and choose **Sign in securely**. To connect a dedicated worker, run the enrollment command on the computer and approve the displayed pairing link with its fingerprint in the authenticated dashboard. Provider logins remain separate and require real supported SDK accounts.

All state is stored in the local Docker volume. **Never** run `docker compose down -v` against a live pilot (it deletes the database). Export encrypted backups to another disk; test restoration before trusting data. Do not commit `.env.local`, backups, tokens, or device key files.

### Limits
- Zero cloud hosting subscription is possible, but electricity, internet, device resources, provider inference, and quota overruns are not guaranteed free.
- Tailscale Personal is intended for permitted personal use, not a commercial public multi-tenant service.
- Only the Caddy gateway is exposed on 127.0.0.1:8791. Tailscale Serve provides private HTTPS without router ports. The PostgreSQL connection is unencrypted **inside this one local Compose network only**, controlled by an explicit pilot-only setting.
- Keycloak imports the realm only on its **first creation**. Editing the JSON later does not overwrite real user accounts.
- This is an owner/browser pilot, not an automatically shipped Flutter APK or a claim of arbitrary website tab control.
- Database, Keycloak and reverse-proxy images still require Docker image pulls and physical acceptance checks. No cloud account is created automatically.

Official docs: https://tailscale.com/docs/reference/tailscale-cli/serve and https://www.keycloak.org/server/importExport

### Encrypted backups (free, no cloud account)
Run `OAGENT_BACKUP_PASSPHRASE=<long-private-value> node backup.mjs` with a unique 20+ character passphrase stored safely outside this PC. The script streams both databases through authenticated AES-256-GCM encryption without writing plaintext dumps to disk. Keep the generated folder and passphrase separately; a backup stored only on the same disk is not disaster recovery.

For a **destructive** restore to your private pilot, stop all active tasks, set the same passphrase and `OAGENT_RESTORE_CONFIRM=I_ACCEPT_DESTRUCTIVE_PILOT_RESTORE`, and run `node restore.mjs /path/to/backup-folder`. Both encrypted files are authenticated before any SQL restore. The script stops web/API/identity services and leaves them stopped if restoration fails. Do not restore a live production tenant this way; test this on an expendable pilot before trusting backups.

### Free approval notifications
On the dashboard Overview screen, choose **Enable approval alerts** and explicitly grant permission. It uses browser Web Push (no paid Firebase project or SMS subscription). Android supports browser push where the installed browser permits it; on iOS/iPadOS, first add the O-AGENT web app to Home Screen (iOS 16.4+). Apple/WebKit document this behavior at https://webkit.org/blog/13878/web-push-for-web-apps-on-ios-and-ipados/ . Device and notification delivery still require a live internet connection, enabled browser notifications and compatible push services; they cannot be guaranteed on every device. Lock-screen payloads never contain prompts or code; open the authenticated app to inspect exact requested actions.

### Easier desktop connection (one command)
After the pilot has been initialized and both devices have Tailscale, from the repository root run `node apps/saas-worker/src/quickstart.mjs /absolute/path/to/your/project` (on Windows, supply the full drive path). The helper reads only the HTTPS origin from your local pilot configuration, generates its own per-device signing key, displays the owner pairing link once, automatically finishes enrollment when approved on your phone, and begins the free workspace-inventory worker. Keep the terminal and computer on. This does not install paid provider SDKs or enable shell/file editing silently.
