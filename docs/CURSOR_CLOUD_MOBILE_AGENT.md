# Cursor Cloud: create agents, supervise runs, inspect screenshots

This is a **development candidate** built on O-AGENT v0.5.0.
It uses the official provider-owned Cursor Cloud Agents API v1, not a
scraper of locally open IDE windows. Cursor's v1 API is in public beta.
Documentation: https://prod.cursor.com/docs/cloud-agent/api/endpoints

## Phone setup

1. Run the updated O-AGENT backend with its **existing persistent vault key**
   configured. On owner-hosted Windows use private Tailscale Serve HTTPS.
2. In the mobile app, open **Remote → Cursor Cloud Agents**. Invited members
   may instead use **My workspace → Agents → Cursor Cloud**.
3. Obtain an API key for your own Cursor account in Cursor Dashboard → API Keys.
   Paste it into the masked credential sheet and verify it.
   Neither an OpenAI API key nor GitHub PAT grants Cursor Cloud access.
4. Tap **Create a hosted coding agent**. Enter an HTTPS repository URL for a
   repository your Cursor account can reach, optionally choose the starting
   branch, then describe the exact task.
5. Default **Plan first** asks the agent to plan. **Implement** requests
   modifications. O-AGENT forces workOnCurrentBranch=false to avoid direct
   pushes to the selected starting ref. Automatic PR creation is opt-in.
6. Review the repository, branch, mode, PR setting, exact prompt, and
   provider-billing warning. Tap **Create cloud agent** to submit.
7. Select the returned agent. Inspect real run status, open **Watch live** for
   provider-reported assistant text and tool statuses, or use **View result**.
8. For ongoing work, **Send prompt** starts a follow-up or **Steer current
   run** when supported. Both require confirmation. Cancel is separate and
   requires confirmation.
9. Under **Generated files and previews**, tap a saved screenshot to
   view/zoom, or tap a PDF/file to open a temporary provider download link.
   Only artifacts the agent actually saved are shown. A screenshot saved
   at a moment in time is not live remote desktop video.

## Authentication, delivery, billing and privacy

- A user's Cursor key is encrypted at rest using O-AGENT's backend AES-GCM
  account vault. It does not ship with the APK. The provider checks actual
  accessible agents and repo permissions.
- New Cloud Agent creates use an explicit per-user request ID from the phone.
  The backend deterministically derives a Cursor bc-UUID agent identifier,
  records an intent before contacting the provider and does not automatically
  repeat ambiguous billable requests.
- A response lost after provider acceptance may leave the creation outcome
  uncertain. Refresh Cursor itself and look for the expected agent ID.
- Ordinary follow-ups and steers also retain their own idempotency records.
  Provider-specific plan/credit limits and rate limits are shown as errors;
  no free usage is implied.
- Signed artifact URLs expire (typically 15 minutes). The backend requires a
  validated relative path beneath artifacts/ and only accepts a provider
  artifact S3 HTTPS hostname. The phone is not given any provider API key.
- The live SSE view forwards only real assistant text, run status, tool name/
  status and final result; it strips thinking, raw tool arguments, raw tool
  results and other provider event types.
- Screenshots may contain secrets, so only fetch them when requested. Users
  should avoid capturing sensitive accounts in agent-generated screenshots.
- No promises of tool-level approval callbacks for Cursor Cloud v1: it is a
  separate API from the explicit Codex CLI app-server permission system.
- Existing ChatGPT browser chats, Claude Code/Copilot SDK sessions, local
  Cursor IDE tabs and VS Code are **not** controlled by this connector.
- Background push delivery, live Windows screen/window streaming, independent
  hosted worker provisioning and a durable multi-instance SaaS database remain
  distinct infrastructure milestones.

## Validation and releases

Automated tests cover API URL/host enforcement, account isolation and key
encryption, run control, SSE filtering, idempotent create/follow-up, safely
ignored path-traversal artifacts and invalid signed URLs. Flutter tests cover
credential sheet/dialog lifecycle, compact layout, run prompt and agent
creation forms. These are protocol-mock tests, not a substitute for a real
Cursor key, agent plan and real-device acceptance.

Run checks on a pull request; APK building is intentionally gated. Use **one
consolidated APK** only after the next complete release milestone passes CI,
and do not commit keys or signed URLs into source or issue screenshots.
