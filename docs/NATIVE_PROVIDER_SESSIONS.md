# Native provider sessions — implementation and acceptance

O-AGENT's **Remote → Continue native provider sessions** lists only Claude Agent
SDK and GitHub Copilot SDK session IDs returned by successfully completed,
worker-authenticated O-AGENT turns. It does **not** scrape unrelated Claude,
Copilot, Cursor IDE, or ChatGPT website conversations.

- A completed SDK turn saves the provider-supplied session ID with its real
  enrolled worker and workspace. The owner-only overview de-duplicates by
  worker, SDK and session identity. Missing, malformed, failed or speculative
  session IDs are never offered.
- Choosing **Continue via native SDK and approval** opens the supervised
  SDK composer with the exact provider, saved session ID, original machine and
  workspace filled in. The user enters a new prompt, reviews it, and confirms
  an explicit approval request before execution.
- An offline/missing original worker disables resume rather than silently
  switching workers or dispatching to an unrelated account. An online worker
  makes a resume attempt eligible, not guaranteed: the official SDK may still
  report a missing, incompatible, or expired session.
- Cursor Cloud agents have an API-backed list, follow-ups, steering, event
  streaming and results under **Remote → Existing Cursor Cloud agents**.
  Codex CLI saved sessions have their own native app-server flow.
- ChatGPT Work has its own mobile/web continuation experience, not a verified
  third-party API exposing arbitrary existing Work sessions or approvals to
  O-AGENT. No cookie extraction or website UI imitation is implemented.
- This is not an always-on deployment. Local SDK turns require the enrolled
  worker online, and provider accounts may require quotas/billing.

## Real-device acceptance before a consolidated APK

1. Start a real authenticated Claude Agent SDK read-only turn from the phone,
   approve it and wait until the SDK returns a nonempty session ID.
2. Refresh Remote. Verify exactly that provider/workspace/worker appears.
3. Tap Continue, enter a harmless follow-up, review and approve it. Confirm
   the SDK resumes the same conversation rather than creating a new one.
4. Repeat with Copilot SDK. Unrelated website conversations must not appear.
5. Stop the original worker. Resume must be disabled. Reconnect and recheck.
6. Delete SDK session persistence or sign out. Resume must fail explicitly
   rather than claim success, or switch to a different thread.
7. Verify member tokens cannot fetch owner overview or approve owner tasks.

Automated checks: `npm run check`, `npm test`,
`flutter analyze --no-pub`, `flutter test --no-pub`. The feature PR
should not build an APK. One consolidated `[mobile-release]` is triggered
only after all checks and manual provider acceptance.
