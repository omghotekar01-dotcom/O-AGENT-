# Free, private O-AGENT pilot
**Not a public SaaS launch.** Your computer runs PostgreSQL, Keycloak, Caddy and the API; it must stay on, and model-provider usage can still cost money.

Install Docker Desktop or compatible Compose and Tailscale on the computer, and Tailscale on your phone. Sign into the same private tailnet on both; enable MagicDNS and HTTPS certificates in Tailnet settings.

```sh
cd deploy/saas/free-pilot
node setup.mjs
docker compose --env-file .env.local -f compose.yaml up -d --build
tailscale serve --bg 8791
```

Run `tailscale serve status` and open the printed HTTPS URL on your phone. **Do not use Tailscale Funnel**, router port forwarding, or a public domain for this personal pilot.

At `https://YOUR-TAILNET-HOST/auth/admin/` sign in to Keycloak's master realm with username `admin` and the generated admin password from your local `.env.local`. Create a user in the `oagent` realm using Keycloak Users → Add user → Credentials. Enable MFA for the account. Registration is disabled; no test password is embedded in this repository.

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
