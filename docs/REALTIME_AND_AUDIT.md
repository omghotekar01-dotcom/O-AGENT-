# Realtime, command and audit protocol

## Source of truth

The database event sequence is authoritative. WebSocket, Broadcast, FCM and WebRTC are transports/notifications, not durable storage. Never infer completion from a socket send or HTTP 202 response.

Every meaningful mutation must persist the entity state change and an outbox event in the same transaction. A dispatcher publishes the outbox event only after commit. Consumers deduplicate by event ID.

## Command envelope

Each user or agent command carries:

- `command_id`: globally unique UUID.
- `idempotency_key`: unique within workspace and command scope.
- `workspace_id`, `project_id`, `agent_id`, `run_id` (where applicable).
- `actor_type` and `actor_id`.
- `expected_version`: reject stale controls where a version check is required.
- `issued_at`, `expires_at`.
- `action`, `target`, validated typed arguments.
- `trace_id` / trace context.
- approval reference when policy requires it.

The server must authenticate the actor, validate workspace membership and device status, verify capability, evaluate policy, validate expiry/version, and persist the command before dispatch.

## Run state machine

`draft → ready → queued → starting → running`

A running task may move to:

- `waiting_for_input`
- `waiting_for_approval`
- `waiting_for_device`
- `paused`
- `recovering`

Terminal states: `completed`, `failed`, `cancelled`.

All transitions are server-controlled, validated against the previous state and persisted with an event. A worker lease has an expiry and a monotonically increasing fencing token; an old worker cannot write after a newer lease has been issued.

## Event envelope

Minimum fields:

- `event_id`, `sequence`, `occurred_at`, `received_at`.
- `workspace_id`, `project_id`, `agent_id`, `run_id`, `session_id`.
- `actor_type`, `actor_id`, `source`.
- `event_type`, `schema_version`, `trace_id`.
- `target`, `argument_hash`, `policy_decision`, `approval_id`.
- `result_status`, `error_code`, `artifact_refs`.
- redacted bounded payload appropriate for the event type.

Event categories include identity/device, provider connection, agent lifecycle, run lifecycle, conversation, tool invocation, computer/browser, terminal, file changes, approvals, policy/security, artifact and deployment.

## Reconnection algorithm

1. Client fetches an authorized snapshot with a server-issued cursor.
2. Client subscribes to the private workspace/run channel with an authorization token.
3. Client fetches all durable events after the cursor.
4. Client merges live notifications and fetched events by `event_id` and monotonic sequence.
5. On reconnect, it repeats from the last acknowledged cursor.
6. If the event retention window has expired, fetch a fresh snapshot and continue from its new cursor.

Never trust client-supplied workspace IDs without server-side membership validation. Private channel authorization must enforce the same tenant boundary as the database API.

## Event types and evidence

- File operations: path, operation, content hash and diff/artifact reference (not raw secret contents).
- Terminal: command metadata, approval record, start/end, exit code and bounded redacted stdout/stderr artifact.
- Computer use: frame timestamp, active application/window metadata where allowed, action event and result. A screenshot is a separate artifact with retention policy.
- Provider calls: provider, model/session IDs, request ID, latency, usage/cost if supplied, retry and error class. Redact secrets and sensitive user content per retention settings.
- Approval: exact action hash, target, requester, approver, decision, expiry and execution result.
- Recovery: lost lease, retry decision, checkpoint, worker identity and resumed sequence.

## Realtime transports

- **App state:** Supabase Realtime private Broadcast; enable private-channel authorization and deny public access.
- **Worker control:** authenticated WSS over an outbound worker connection, coordinated through a stateful relay (for example Cloudflare Durable Objects).
- **Screen/media:** WebRTC with DTLS-SRTP and authenticated signaling. Use short-lived TURN credentials. Track live/degraded/disconnected quality states.
- **Push:** FCM sends a minimal notification and deep link; sensitive content remains behind authenticated fetch.

## No-fake UI contract

- `connected` means authenticated and last health check succeeded.
- `degraded` means authenticated but a required health/capability check is failing.
- `expired` and `revoked` are distinct.
- `live` means a fresh frame/event has arrived within the configured freshness window and the transport is active.
- Stale cached events are visibly marked as stale/offline.
- The UI must never locally advance a run to completed before the server's durable terminal event arrives.
