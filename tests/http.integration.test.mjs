import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { randomBytes } from "node:crypto";
import { createServer } from "node:net";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

async function unusedPort() {
  return new Promise((done, fail) => {
    const server = createServer();
    server.once("error", fail);
    server.listen(0, "127.0.0.1", () => {
      const port = server.address().port;
      server.close(() => done(port));
    });
  });
}
const apiToken = "0123456789abcdef0123456789abcdef";
const workerToken = "fedcba9876543210fedcba9876543210";

test("HTTP API authenticates, dispatches and persists actual lifecycle", { timeout: 20000 }, async () => {
  const port = await unusedPort();
  const directory = mkdtempSync(join(tmpdir(), "oagent-test-"));
  const child = spawn(process.execPath, [resolve("apps/control-plane/src/server.mjs")], {
    env: { ...process.env, HOST: "127.0.0.1", PORT: String(port), OAGENT_API_TOKEN: apiToken, OAGENT_WORKER_TOKEN: workerToken, OAGENT_DATA_FILE: join(directory, "state.json"), OAGENT_VAULT_KEY_BASE64: randomBytes(32).toString("base64"), OAGENT_GITHUB_REPOS: "", OAGENT_ENABLE_CODEX_CLOUD_SYNC: "1", OAGENT_ENABLE_CODEX_LOCAL_SYNC: "1" },
    stdio: "ignore",
  });
  const url = `http://127.0.0.1:${port}`;
  async function call(path, token, method = "GET", body, key) {
    const response = await fetch(url + path, {
      method,
      headers: { authorization: `Bearer ${token}`, ...(body ? { "content-type": "application/json" } : {}), ...(key ? { "idempotency-key": key } : {}) },
      body: body ? JSON.stringify(body) : undefined,
    });
    return { status: response.status, payload: await response.json() };
  }
  try {
    let ready = false;
    for (let i = 0; i < 80; i++) {
      if (child.exitCode !== null) throw Error("Control-plane process exited before startup");
      try { ready = (await fetch(url + "/health")).ok; if (ready) break; } catch { /* startup pending */ }
      await new Promise(r => setTimeout(r, 100));
    }
    assert.equal(ready, true, "Control-plane HTTP server must start");
    const config = await call("/api/auth/config", "none");
    assert.equal(config.status, 200);
    assert.equal(config.payload.enabled, false, "Public registration must fail closed without email and HTTPS settings");
    const publicRegister = await call("/api/auth/register", "none", "POST", {
      email: "tester@example.org", displayName: "User", password: "a-secure-password-123"
    });
    assert.equal(publicRegister.status, 503);
    // Invitation-only members are separate identities. A member must never
    // become an operator simply by connecting to the same host.
    const whoOwner = await call("/api/me", apiToken);
    assert.equal(whoOwner.payload.role, "owner");
    assert.equal(whoOwner.payload.vaultReady, true);
    assert.equal((await call("/api/accounts/invitations", workerToken, "POST",
      { label: "Unauthorized request" })).status, 401);
    const invited = await call("/api/accounts/invitations", apiToken, "POST",
      { label: "Mobile tester" });
    assert.equal(invited.status, 201);
    const oneUseCode = invited.payload.invitationCode;
    assert.match(oneUseCode, /^join_/);
    const joinedMember = await call("/api/accounts/claim", "not-an-authenticated-member", "POST",
      { invitationCode: oneUseCode, displayName: "Invited tester" });
    assert.equal(joinedMember.status, 201);
    const personalToken = joinedMember.payload.token;
    assert.equal((await call("/api/accounts/claim", "bad", "POST",
      { invitationCode: oneUseCode, displayName: "Replay" })).status, 401);
    assert.equal((await call("/api/me", personalToken)).payload.role, "member");
    assert.equal((await call("/api/state", personalToken)).payload.workers.length, 0);
    assert.equal((await call("/api/projects", personalToken)).status, 403);
    // Remote coding-agent sessions and approvals are strictly owner-only.
    assert.equal((await call("/api/remote/overview", personalToken)).status, 403);
    const remote = await call("/api/remote/overview", apiToken);
    assert.equal(remote.status, 200);
    assert.equal(remote.payload.screenStreaming.supported, false);
    assert.equal(remote.payload.activeRuns, 0);
    assert.ok(Array.isArray(remote.payload.sources));
    assert.equal((await call("/api/ai/threads", personalToken)).status, 403);
    assert.equal((await call("/api/workers/register", personalToken, "POST",
      { id: "bad-guest", name: "Impostor" })).status, 401);
    assert.equal((await call("/api/tasks", personalToken, "POST",
      { workerId: "ci-worker", kind: "system_info" })).status, 403);
    assert.equal((await call("/api/accounts/invitations", personalToken, "POST",
      { label: "Guest cannot invite" })).status, 403);
    const publicConnectionState = await call("/api/account/connections", personalToken);
    assert.equal(publicConnectionState.status, 200);
    assert.equal(publicConnectionState.payload.vaultReady, true);
    assert.equal(publicConnectionState.payload.providers.every(p => !p.connected), true);
    // Cursor Cloud credentials are per account; they cannot unlock worker routes.
    assert.equal((await call("/api/account/cursor", personalToken)).payload.connected, false);
    assert.equal((await call("/api/account/cursor/agents", personalToken)).status, 409);
    assert.equal((await call("/api/account/cursor/agents/bc-00000000/runs/run-00000000/stream", personalToken)).status, 409);
    assert.equal((await call("/api/account/cursor/agents", workerToken)).status, 401);
    assert.equal((await call("/api/account/cursor", apiToken)).payload.connected, false);
    const personalKey = "fake-provider-key-safe-for-tests-123456789";
    const connected = await call("/api/account/connections/gemini", personalToken, "PUT",
      { apiKey: personalKey, model: "gemini-2.5-flash" });
    assert.equal(connected.status, 200);
    assert.equal(connected.payload.providers.find(p => p.id === "gemini").connected, true);
    assert.equal(JSON.stringify(connected.payload).includes(personalKey), false);
    const txt = Buffer.from("Integration test private notes").toString("base64");
    const upload = await call("/api/account/attachments", personalToken, "POST", {
      name: "my-notes.txt", mimeType: "text/plain", base64: txt
    });
    assert.equal(upload.status, 201);
    assert.equal(upload.payload.name, "my-notes.txt");
    const list = await call("/api/account/attachments", personalToken);
    assert.equal(list.payload.attachments.length, 1);
    assert.equal(JSON.stringify(list.payload).includes("Integration test private notes"), false);
    assert.equal((await call("/api/account/attachments", apiToken)).payload.attachments.length, 0);
    assert.equal((await call("/api/account/attachments/" + upload.payload.id, apiToken, "DELETE")).status, 404);
    assert.equal((await call("/api/account/attachments/" + upload.payload.id, personalToken, "DELETE")).status, 200);
    const ownerConnections = await call("/api/account/connections", apiToken);
    assert.equal(ownerConnections.payload.providers.find(p => p.id === "gemini").connected, false);
    const stateFile = await import("node:fs").then(fs =>
      fs.readFileSync(join(directory, "state.json"), "utf8"));
    assert.equal(stateFile.includes(personalKey), false);
    assert.equal(stateFile.includes(personalToken), false);
    assert.equal(stateFile.includes(oneUseCode), false);
    const removeKey = await call("/api/account/connections/gemini", personalToken, "DELETE");
    assert.equal(removeKey.status, 200);
    assert.equal(removeKey.payload.providers.find(p => p.id === "gemini").connected, false);
    assert.equal((await call("/api/accounts/members", apiToken)).payload.members.length, 1);
    const revoked = await call("/api/accounts/members/" + joinedMember.payload.user.id, apiToken, "DELETE");
    assert.equal(revoked.status, 200);
    assert.equal((await call("/api/me", personalToken)).status, 401);

    assert.equal((await call("/api/state", "wrong")).status, 401);
    assert.equal((await call("/api/ai/status", "wrong")).status, 401);
    const providerStatus = await call("/api/ai/status", apiToken);
    assert.equal(providerStatus.status, 200);
    assert.equal(providerStatus.payload.configured, false);
    const unconfiguredChat = await call("/api/ai/chat", apiToken, "POST", { agentId: "navigator", message: "Check machine status" });
    assert.equal(unconfiguredChat.status, 503);
    assert.match(unconfiguredChat.payload.error, /not configured/i);

    assert.equal((await call("/api/projects", "wrong")).status, 401);
    const initialHub = await call("/api/projects", apiToken);
    assert.equal(initialHub.status, 200);
    assert.equal(initialHub.payload.projects.length, 0);
    const owned = await call("/api/projects", apiToken, "POST", { title: "My genuine project", description: "Acceptance test" });
    assert.equal(owned.status, 201);
    assert.equal(owned.payload.source, "oagent");
    assert.equal((await call("/api/projects/" + owned.payload.id, apiToken)).payload.project.title, "My genuine project");
    assert.equal((await call("/api/projects/" + owned.payload.id + "/messages", apiToken, "POST",
      { agentId: "navigator", message: "Hello" })).status, 503);
    assert.equal((await call("/api/projects/github%3Aunknown%2Frepo", apiToken)).status, 404);
    assert.equal((await call("/api/integrations", apiToken)).payload.sources.some(s => s.id === "chatgpt_work" && s.status === "unsupported"), true);

    const registered = await call("/api/workers/register", workerToken, "POST", { id: "ci-worker", name: "CI worker" });
    assert.equal(registered.status, 201);
    assert.equal(registered.payload.name, "CI worker");
    const localSessions = { sessions: [
      { id: "11111111-2222-4333-8444-555555555555",
        cwd: "C:\\Users\\ASUS\\O-AGENT-", title: "Work on project",
        state: "notLoaded", updatedAt: "2026-11-12T15:00:00Z" },
    ] };
    assert.equal((await call("/api/workers/ci-worker/codex/local/sync",
      apiToken, "POST", localSessions)).status, 401);
    const localSync = await call("/api/workers/ci-worker/codex/local/sync",
      workerToken, "POST", localSessions);
    assert.equal(localSync.status, 200);
    assert.equal(localSync.payload.projectCount, 1);
    const localFeed = await call("/api/projects", apiToken);
    const workspace = localFeed.payload.projects.find(p => p.source === "codex_cli");
    assert.equal(workspace.title, "O-AGENT-");
    assert.equal(workspace.state, "history_available");
    assert.equal((await call("/api/projects/" + workspace.id, apiToken)).payload.project.sessions[0].title,
      "Work on project");

    const localTurn = await call("/api/providers/codex/local/turns", apiToken, "POST", {
      projectId: workspace.id, sessionId: "11111111-2222-4333-8444-555555555555",
      prompt: "Read and summarize the code safely", mode: "workspace_write",
    }, "codex-local-turn-http-123456");
    assert.equal(localTurn.status, 201);
    assert.equal(localTurn.payload.status, "waiting_for_approval");
    assert.equal((await call("/api/tasks/" + localTurn.payload.id, "wrong")).status, 401);
    assert.equal((await call("/api/workers/ci-worker/next", workerToken, "POST")).payload.task, null);
    const approvalTurn = await call("/api/tasks/" + localTurn.payload.id + "/decision", apiToken,
      "POST", { approve: true });
    assert.equal(approvalTurn.payload.status, "queued");
    const activeTurn = await call("/api/workers/ci-worker/next", workerToken, "POST");
    assert.equal(activeTurn.payload.task.kind, "codex_cli_turn");
    assert.equal(activeTurn.payload.task.parameters.cwd, "C:\\Users\\ASUS\\O-AGENT-");
    assert.equal((await call("/api/workers/ci-worker/tasks/" + localTurn.payload.id + "/update",
      apiToken, "POST", { type: "agent_delta", text: "Private text" })).status, 401);
    const eventSent = await call("/api/workers/ci-worker/tasks/" + localTurn.payload.id + "/update",
      workerToken, "POST", { type: "agent_delta", text: "Real Codex message" });
    assert.equal(eventSent.status, 200);
    const permission = await call("/api/workers/ci-worker/tasks/" + localTurn.payload.id + "/approvals",
      workerToken, "POST", { id: "approval-real-123456", kind: "command", description: "Run npm test" });
    assert.equal(permission.status, 201);
    assert.equal(permission.payload.state, "pending");
    assert.equal((await call("/api/workers/ci-worker/tasks/" + localTurn.payload.id +
      "/approvals/approval-real-123456", workerToken)).payload.state, "pending");
    assert.equal((await call("/api/tasks/" + localTurn.payload.id +
      "/approvals/approval-real-123456/decision", "bad", "POST", { approve: true })).status, 401);
    const decided = await call("/api/tasks/" + localTurn.payload.id +
      "/approvals/approval-real-123456/decision", apiToken, "POST", { approve: false });
    assert.equal(decided.payload.state, "denied");
    assert.equal((await call("/api/workers/ci-worker/tasks/" + localTurn.payload.id +
      "/approvals/approval-real-123456", workerToken)).payload.state, "denied");
    const endedTurn = await call("/api/workers/ci-worker/tasks/" + localTurn.payload.id + "/finish",
      workerToken, "POST", { ok: true, result: { providerStatus: "completed", output: "Real Codex message" } });
    assert.equal(endedTurn.payload.status, "completed");
    const reloadedTurn = await call("/api/tasks/" + localTurn.payload.id, apiToken);
    assert.equal(reloadedTurn.payload.updates[0].text, "Real Codex message");
    assert.equal(reloadedTurn.payload.result.output, "Real Codex message");

    const codexData = { tasks: [{ id: "abcd-1234", title: "Real external task metadata",
      status: "in_progress", url: "https://chatgpt.com/codex/tasks/abcd-1234" }] };
    assert.equal((await call("/api/workers/ci-worker/codex/sync", apiToken, "POST", codexData)).status, 401);
    const synced = await call("/api/workers/ci-worker/codex/sync", workerToken, "POST", codexData);
    assert.equal(synced.status, 200);
    assert.equal(synced.payload.accepted, 1);
    const fullHub = await call("/api/projects", apiToken);
    assert.ok(fullHub.payload.projects.some(p => p.source === "codex_cloud" && p.state === "in_progress"));
    const codexRequest = await call("/api/providers/codex/tasks", apiToken, "POST", {
      workerId: "ci-worker", environmentId: "test-cloud-env", prompt: "Create a website",
    }, "codex-http-request-0001");
    assert.equal(codexRequest.status, 201);
    assert.equal(codexRequest.payload.status, "waiting_for_approval");
    assert.equal((await call("/api/workers/ci-worker/next", workerToken, "POST")).payload.task, null);
    const codexApproval = await call("/api/tasks/" + codexRequest.payload.id + "/decision", apiToken,
      "POST", { approve: true });
    assert.equal(codexApproval.payload.status, "queued");
    const codexClaim = await call("/api/workers/ci-worker/next", workerToken, "POST");
    assert.equal(codexClaim.payload.task.kind, "codex_cloud_submit");
    assert.equal(codexClaim.payload.task.parameters.prompt, "Create a website");
    const codexSent = await call("/api/workers/ci-worker/tasks/" + codexRequest.payload.id + "/finish",
      workerToken, "POST", { ok: true, result: { state: "submitted_to_provider" } });
    assert.equal(codexSent.payload.result.state, "submitted_to_provider");

    const initial = await call("/api/state", apiToken);
    assert.equal(initial.payload.workers[0].status, "online");
    const task = await call("/api/tasks", apiToken, "POST", { workerId: "ci-worker", kind: "system_info" }, "http-test-task-0001");
    assert.equal(task.status, 201);
    assert.equal(task.payload.status, "queued");
    const claimed = await call("/api/workers/ci-worker/next", workerToken, "POST");
    assert.equal(claimed.payload.task.id, task.payload.id);
    const finish = await call(`/api/workers/ci-worker/tasks/${task.payload.id}/finish`, workerToken, "POST", { ok: true, result: { measured: 42 } });
    assert.equal(finish.payload.status, "completed");
    const inventory = await call("/api/tasks", apiToken, "POST", { workerId: "ci-worker", kind: "workspace_inventory" }, "http-test-task-0002");
    assert.equal(inventory.payload.status, "waiting_for_approval");
    assert.equal((await call("/api/workers/ci-worker/next", workerToken, "POST")).payload.task, null);
    const rejected = await call(`/api/tasks/${inventory.payload.id}/decision`, apiToken, "POST", { approve: false });
    assert.equal(rejected.payload.status, "rejected");
    const result = await call("/api/events?after=0", apiToken);
    assert.ok(result.payload.events.some(event => event.type === "task.completed"));
    const duplicate = await call("/api/tasks", apiToken, "POST", { workerId: "ci-worker", kind: "system_info" }, "http-test-task-0001");
    assert.equal(duplicate.payload.id, task.payload.id);
  } finally {
    child.kill("SIGTERM");
    rmSync(directory, { recursive: true, force: true });
  }
});
