# Native SDK saved-session discovery — development integration

The laptop worker can now use the **official Claude Agent SDK** and **GitHub Copilot SDK** to discover saved sessions beyond O-AGENT-created runs, as long as those SDK capabilities were explicitly enabled on the trusted laptop.

## Security and scope

- Worker SDK discovery runs about every 2 minutes and is best-effort. It never blocks real task execution or heartbeats.
- Only saved sessions whose actual, canonical directory is inside the enrolled `OAGENT_WORKSPACE_ROOT` are included. Out-of-root sessions and symlink escapes are skipped.
- The worker sends at most 40 records containing provider kind, session ID, folder, short display title, and optional modification time.
- Full transcripts, model private reasoning, API keys, browser cookies, tool arguments and environment secrets are excluded.
- The backend keeps snapshots **in memory**, not JSON state, for at most five minutes. Only owner-authenticated clients may read them via `GET /api/remote/overview`.
- A disconnected worker or a disabled SDK capability cannot advertise an actionable session.
- An existing saved session is not an in-progress interactive IDE tab. Resuming through the SDK requires the owner's exact approval, may be rejected as busy/unavailable, and does not bypass the original provider's permissions.

## Physical acceptance

1. On your personal machine, sign into the official Claude Code/Copilot CLI account and install its optionally pinned SDK, using the same Windows account as O-AGENT.
2. Set the enrolled workspace root to the parent of the projects you specifically want to share. Enable each provider capability separately; unrelated directories must stay hidden.
3. Start O-AGENT and open Android **Remote → Continue native provider sessions**. Existing saved sessions from the enrolled root should appear after successful metadata sync.
4. Choose a harmless session, enter a read-only prompt, inspect the exact provider, worker, folder and session ID, and approve the run. Confirm the actual provider resumes the same session.
5. Verify duplicate runs do not create duplicate entries, and unplug/offline the laptop to ensure the session becomes non-actionable. Test provider logout, missing SDK, bad login, expired permissions, wrong folder and transport errors.
6. Verify only the owner can view these records. Invited member accounts must not access native session metadata or approvals.

## Explicit exclusions

No API currently implemented here makes arbitrary ChatGPT Work browser conversations, private Cursor IDE tabs, Claude web sessions, or internal website approvals controllable through O-AGENT. These require separate officially authorized integrations.

This branch is not a signed production APK and does not provision cloud hosting, OAuth production enrollment, durable multi-tenant identity, or a production audit database.

Official technical references:
- https://platform.claude.com/cookbook/claude-agent-sdk-05-building-a-session-browser
- https://docs.github.com/en/copilot/how-tos/copilot-sdk/troubleshooting/compatibility
