import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
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
    env: { ...process.env, HOST: "127.0.0.1", PORT: String(port), OAGENT_API_TOKEN: apiToken, OAGENT_WORKER_TOKEN: workerToken, OAGENT_DATA_FILE: join(directory, "state.json"), OAGENT_GITHUB_REPOS: "", OAGENT_ENABLE_CODEX_CLOUD_SYNC: "1" },
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
