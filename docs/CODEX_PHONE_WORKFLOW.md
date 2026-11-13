# O-AGENT v0.6.2: Continue your real Codex projects from your phone

This release focuses on ONE everyday goal: inspect actual saved Codex
conversation messages on your Windows laptop, send the next instruction to
that saved conversation when supported, and review each permission request.
Other provider integrations remain optional.

## First-time setup (no additional API key for reading saved Codex history)

1. On your Windows laptop, install and sign in to the official Codex CLI
   using the same Windows user account that runs O-AGENT. Make sure a
   real Codex project/conversation already exists in Codex history.
2. Run CONFIGURE-PROJECTS.cmd once. Enable "Sync MY local Codex CLI /
   IDE projects". Run O-AGENT.cmd and keep the Windows worker online.
3. Connect the laptop and Android phone with private Tailscale, even from
   different Wi-Fi networks. Where another app uses port 443, use the
   separate private O-AGENT HTTPS origin already confirmed on port 8443.
   Do not reset Tailscale Serve or overwrite the other application's route.
4. In the phone app choose My owner workspace and connect with that
   private HTTPS backend URL and the operator token saved on your laptop.
   Do not use a Codex API key here; never post tokens to chat or screenshots.
5. Open Remote > My Codex conversations. Select a real recent conversation.
   Older records are available under Browse all conversations and Projects.
6. Tap Load saved messages. This reads owner-selected user and assistant
   text via the Codex app-server thread/read method and does NOT take
   control of the existing active Codex window.
7. Use Progress update, What next?, Explain error or your own instruction.
   These are free editable text templates, not a separate paid AI agent.
8. Start with Read-only, tap the send arrow, inspect the EXACT text and
   choose Approve and send. This one action authorizes that exact prompt.
   Codex may need your existing subscription/credits to complete it.
   In Project edits mode, separate command/file change permissions still
   require individual approval or rejection.
9. Output and approvals trigger authenticated server events and task
   refresh, with periodic polling as a fallback. Network and provider
   delays are real and zero-latency operation is not guaranteed.

## Meaningful errors, not just "Provider error"

CODEX_SESSION_BUSY: Another Codex application owns the live writing thread.
You can still read its saved messages. Finish its active turn on the laptop
before trying to resume it from O-AGENT. This feature does not inject into
an independently running terminal or ChatGPT website browser tab.

CODEX_HISTORY_NOT_FOUND: The selected record is no longer accessible under
the signed-in Windows user's Codex account. Refresh the projects list.

CODEX_LOGIN_REQUIRED: Sign into Codex on the same Windows account as the
O-AGENT worker. Check that Codex CLI can be started.

CODEX_UPDATE_REQUIRED: The installed Codex CLI cannot perform the requested
app-server history operation. Update the official CLI and restart O-AGENT.

CODEX_HISTORY_TOO_LARGE: The official app-server returned a conversation
beyond this mobile preview's bounded capacity. View the full history in
the original Codex application on the laptop.

No recent desktop image: The user-selected display-sharing browser stopped
sending fresh frames. Check the browser sharing indicator, laptop sleep state
and private Tailscale route. Stop and restart the consensual capture as needed.

## Privacy and limitations

- Only the workspace owner can request a saved Codex history task. The
  backend verifies the session was discovered under a recently synced
  enrolled worker.
- The child Codex process inherits a short allowlist of OS/Codex home
  variables, not the O-AGENT operator token, worker token, vault key, GitHub
  secret, or other AI provider API keys.
- History parsing accepts only user text, assistant text and plans; it does
  not export hidden reasoning, raw tool arguments or tool output.
- A mobile preview contains at most 20 recent turns, 32 message cards
  and 13,000 characters. Content supplied by users themselves may include
  sensitive information. Use only a trusted private O-AGENT backend.
- Saved messages are held in server memory for at most 30 minutes, never
  in the durable task database. Reload the conversation after expiry or
  a backend restart. The original saved history stays on the laptop.
- This does not take over an independently running ChatGPT website tab,
  arbitrary Cursor IDE, Claude, Gemini or Copilot consumer conversation.
  Each agent needs a supported, explicitly authenticated integration.
- The screen preview is consented and view-only, not unrestricted remote
  mouse/keyboard or hidden unattended desktop capture. Browser throttling
  may still reduce frame rate.
- No paid API key is needed to read existing Codex history, but making
  new Codex turns can use the user's existing provider account quota.
  No paid credentials or "free API keys" are bundled with the app.

## Acceptance gates

Backend: npm run check and npm test, including selected-session isolation,
read-only conversation retrieval, no persisted transcript, token separation,
accurate error categories, and idempotent explicit prompt confirmation.

Flutter: flutter analyze and flutter test, including compact Android width,
real saved chat bubbles, correct editable prompts, and approval confirmation.

Windows: one-click launcher security checks and an authenticated Codex CLI
worker. Real-device acceptance still needs a working laptop Codex login,
phone-to-laptop private HTTPS access, live app-server reads and an actual
approved/denied turn. Automated mocks are NOT proof of real-provider success.

Use ONE consolidated native APK release only after all source checks pass.
Do not create a new APK for each small source change.
