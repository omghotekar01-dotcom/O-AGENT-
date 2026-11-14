# O-AGENT native owner approval inbox (development)

The mobile Remote screen now brings all **O-AGENT-managed** task approvals and
supported SDK/Codex tool-permission requests together in one review feed.
The owner-only `GET /api/remote/overview` provides `approvalInbox`,
`approvalInboxSummary`, and `schemaVersion`.

For every item, the phone fetches the latest task from the owner-only endpoint,
checks the task identity/state, and requires a visible, exact-text confirmation
before submitting an approve/deny decision using the existing owner API.
Tool approval expiry is rechecked on the server. An offline worker is
not presented as immediately actionable.

This is **not** a general-purpose host approval interception mechanism. It
does not claim access to approvals inside arbitrary ChatGPT Work, Cursor
IDE, Claude web or other third-party consumer tabs. It also does not
authorize desktop capture, create OAuth scopes, or bypass SDK security.

## Acceptance and commercial gates

- Verify true pending Codex/Claude/Copilot permissions appear once only.
- Verify tool permissions disappear once expired/decided and approval of stale
  requests fails server-side; background/foreground refreshes should be safe.
- Verify task-level approvals including workspace inventory are counted,
  reviewable and denyable. Do not confuse backend receipt with provider
  execution confirmation.
- Verify worker offline and cross-account access are denied; member tokens
  cannot read the owner inbox.
- Test narrow Android widths, font scaling, rotation and no-network recovery.
- Observe real provider SDK behavior with actual consented accounts; protocol
  mocks and automated CI alone are insufficient for commercial readiness.
- Production still requires signed releases, real identity, private durable
  storage, stronger authorization, tenant isolation, monitoring and backups.

No APK build should be triggered for a pull request. Batch native releases
after automated and physical acceptance tests.
