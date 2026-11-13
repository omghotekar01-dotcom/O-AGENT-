import test from "node:test";
import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { ControlPlane } from "../apps/control-plane/src/core.mjs";
import { AccountHub } from "../apps/control-plane/src/account-hub.mjs";
import { CursorCloudClient } from "../apps/control-plane/src/cursor-cloud.mjs";

const agent = "bc-00000000-0000-0000-0000-000000000001";
const run = "run-00000000-0000-0000-0000-000000000002";
function cursorMock() {
  const calls = [];
  const transport = async (url, opts) => {
    calls.push({ url, opts });
    assert.ok(url.startsWith("https://api.cursor.com/v1/"));
    const path = new URL(url).pathname;
    const result = path === "/v1/me"
      ? { userEmail: opts.headers.Authorization.endsWith("key-alice-123456789")
          ? "alice@example.test" : "bob@example.test", apiKeyName: "My agent key" }
      : path === "/v1/agents" ? { items: [{
        id: agent, name: "Build the product", status: "IDLE",
        url: "https://cursor.com/agents/" + agent,
        latestRunId: run, updatedAt: "2026-11-13T00:00:00Z",
      }] }
      : path.endsWith("/cancel") ? { id: run }
      : path.endsWith("/runs/" + run) ? { id: run, agentId: agent, status: "FINISHED",
        result: "Implemented real files.", git: { branches: [{
          repoUrl: "github.com/user/repo", branch: "feature",
          prUrl: "https://github.com/user/repo/pull/1",
        }] } }
      : path.endsWith("/runs") && opts.method === "POST"
        ? JSON.parse(opts.body).delivery === "steer"
          ? { delivery: "steered", runId: run }
          : { run: { id: run, agentId: agent, status: "CREATING" } }
        : path.endsWith("/runs") ? { items: [{ id: run, agentId: agent, status: "RUNNING" }] }
          : { id: agent, name: "Build the product", status: "IDLE",
            repos: [{ url: "https://github.com/user/repo", startingRef: "main" }] };
    return { ok: true, status: 200, text: async () => JSON.stringify(result) };
  };
  return { calls, transport };
}
function fixture() {
  let saved = "";
  const core = new ControlPlane({}, data => saved = JSON.stringify(data));
  const remote = cursorMock();
  const hub = new AccountHub(core, {
    env: { OAGENT_VAULT_KEY_BASE64: randomBytes(32).toString("base64") },
    fetchImpl: remote.transport, now: () => 1794500000000,
  });
  const alice = hub.claimInvitation({
    invitationCode: hub.createInvitation({ label: "Alice" }).invitationCode,
    displayName: "Alice",
  });
  const bob = hub.claimInvitation({
    invitationCode: hub.createInvitation({ label: "Bob" }).invitationCode,
    displayName: "Bob",
  });
  return { core, hub, remote, alice: alice.user.id, bob: bob.user.id,
    persisted: () => saved };
}
test("verified Cloud Agent v1 client uses fixed Cursor origin, safe output and real run endpoints", async () => {
  const { calls, transport } = cursorMock();
  const client = new CursorCloudClient({ fetchImpl: transport });
  assert.equal((await client.verify("key-alice-123456789")).identity, "alice@example.test");
  const list = await client.listAgents("key-alice-123456789");
  assert.equal(list.agents[0].id, agent);
  assert.equal((await client.getAgent("key-alice-123456789", agent)).repos[0].ref, "main");
  assert.equal((await client.listRuns("key-alice-123456789", agent)).runs[0].status, "RUNNING");
  assert.equal((await client.getRun("key-alice-123456789", agent, run)).result, "Implemented real files.");
  assert.equal((await client.followUp("key-alice-123456789", agent,
    { prompt: "Fix tests" })).run.status, "CREATING");
  assert.equal((await client.followUp("key-alice-123456789", agent,
    { prompt: "Also test mobile", delivery: "steer" })).delivery, "steered");
  assert.equal((await client.cancelRun("key-alice-123456789", agent, run)).cancelled, true);
  assert.equal(calls.length, 8);
  assert.ok(calls.every(c => c.opts.headers.Authorization === "Bearer key-alice-123456789"));
  await assert.rejects(client.getRun("key-alice-123456789", "../../secret", run),
    /Invalid agent ID/);
  await assert.rejects(client.followUp("key-alice-123456789", agent,
    { prompt: "hi", delivery: "force" }), /Invalid delivery/);
});
test("per-user Cursor keys are encrypted, isolated, revocable and not confused with chatbot keys", async () => {
  const { core, hub, remote, alice, bob, persisted } = fixture();
  assert.equal(hub.cursorStatus(alice).connected, false);
  hub.connectCursor(alice, { apiKey: "key-alice-123456789" });
  hub.connectCursor(bob, { apiKey: "key-bob-123456789" });
  assert.equal(persisted().includes("key-alice-123456789"), false);
  assert.equal(persisted().includes("key-bob-123456789"), false);
  assert.equal(hub.cursorStatus(alice).status, "configured_unverified");
  assert.equal(hub.listConnections(alice).providers.some(p => p.id === "cursor"), false);
  await hub.verifyCursor(alice);
  await hub.verifyCursor(bob);
  assert.equal(hub.cursorStatus(alice).identity, "alice@example.test");
  assert.equal(hub.cursorStatus(bob).identity, "bob@example.test");
  await hub.cursorAgents(alice);
  assert.equal(remote.calls.at(-1).opts.headers.Authorization, "Bearer key-alice-123456789");
  await hub.cursorAgents(bob);
  assert.equal(remote.calls.at(-1).opts.headers.Authorization, "Bearer key-bob-123456789");
  assert.equal(JSON.stringify(hub.cursorStatus(alice)).includes("key-alice-123456789"), false);
  assert.throws(() => hub.decrypt(bob, "cursorCloud",
    core.data.accounts.integrations[alice].cursorCloud.secret), /could not be decrypted/);
  hub.disconnectCursor(alice);
  await assert.rejects(hub.cursorAgents(alice), /Connect your own Cursor/);
  assert.equal(hub.cursorStatus(bob).connected, true);
  hub.revokeMember(bob);
  assert.equal(hub.cursorStatus(bob).connected, false);
});
test("explicit follow-up/steer is idempotent and uncertain network delivery is never retried silently", async () => {
  const { hub, remote, alice } = fixture();
  hub.connectCursor(alice, { apiKey: "key-alice-123456789" });
  const params = { prompt: "Add integration tests", requestId: "unique-request-12345" };
  const first = await hub.cursorFollowUp(alice, agent, params);
  assert.equal(first.run.id, run);
  assert.deepEqual(await hub.cursorFollowUp(alice, agent, params), first);
  assert.equal(remote.calls.filter(c => c.url.endsWith("/runs") && c.opts.method === "POST").length, 1);
  await assert.rejects(hub.cursorFollowUp(alice, agent, {
    prompt: "A different request", requestId: params.requestId,
  }), /reused/);
  await assert.rejects(hub.cursorFollowUp(alice, agent, { prompt: "not valid",
    requestId: "abc" }), /unique request ID/);
  assert.equal((await hub.cursorFollowUp(alice, agent, { prompt: "steer safely",
    requestId: "another-unique-request-999", delivery: "steer" })).delivery, "steered");
  const failing = async () => { throw Error("transport lost, outcome unknown"); };
  hub.cursor = new CursorCloudClient({ fetchImpl: failing });
  const uncertain = { prompt: "Unknown response", requestId: "third-unique-request-123" };
  await assert.rejects(hub.cursorFollowUp(alice, agent, uncertain), /Check the run before retrying/);
  await assert.rejects(hub.cursorFollowUp(alice, agent, uncertain), /outcome is uncertain/);
});
test("provider failures expose safe codes and never echo upstream secret strings", async () => {
  const client = new CursorCloudClient({ fetchImpl: async () => ({
    ok: false, status: 403, text: async () => JSON.stringify({
      error: { code: "plan_required", message: "secret-key-12345" },
    }),
  }) });
  await assert.rejects(client.verify("private-key-123456"), error =>
    error.status === 403 && /plan required/.test(error.message) &&
    !error.message.includes("secret-key"));
  const wrong = new CursorCloudClient({ fetchImpl: async () => ({
    ok: true, status: 200, text: async () => JSON.stringify({
      items: [{ id: agent, name: "X", url: "https://evil.test/steal" }],
    }),
  }) });
  const agents = await wrong.listAgents("private-key-123456");
  assert.equal(agents.agents[0].url, null);
});

test("run SSE forwards assistant and tool status but drops thinking and tool args", async () => {
  const emitted = [
    'event: status\ndata: {"runId":"' + run + '","status":"RUNNING"}\n\n',
    'id: 1713033005000-0\nevent: thinking\ndata: {"text":"secret internal reasoning"}\n\n',
    'id: 1713033006000-0\nevent: assistant\ndata: {"text":"Real work in progress"}\n\n',
    'id: 1713033007000-0\nevent: tool_call\ndata: {"name":"read_file","status":"completed","args":{"path":"/secret"},"result":{"content":"SENSITIVE"}}\n\n',
    'id: 1713033008000-0\nevent: result\ndata: {"text":"Completed work","status":"FINISHED"}\n\n',
    'id: 1713033009000-0\nevent: done\ndata: {}\n\n',
  ].join("");
  let capturedHeaders;
  const client = new CursorCloudClient({ fetchImpl: async (url, opts) => {
    assert.ok(url.endsWith("/runs/" + run + "/stream"));
    capturedHeaders = opts.headers;
    return { ok: true, status: 200,
      body: new ReadableStream({ start(controller) {
        const encoded = new TextEncoder().encode(emitted);
        controller.enqueue(encoded.subarray(0, 41));
        controller.enqueue(encoded.subarray(41));
        controller.close();
      } }) };
  } });
  const events = [];
  for await (const item of client.streamRun("key-alice-123456789", agent, run,
    { lastEventId: "1713033004000-0" })) events.push(item);
  assert.deepEqual(events.map(e => e.event),
    ["status", "assistant", "tool_call", "result", "done"]);
  assert.equal(events[1].data.text, "Real work in progress");
  assert.deepEqual(events[2].data, { name: "read_file", status: "completed" });
  assert.equal(capturedHeaders["Last-Event-ID"], "1713033004000-0");
  assert.doesNotMatch(JSON.stringify(events), /SENSITIVE|secret internal reasoning|\/secret/);
});
test("expired Cursor SSE forces a fresh run read, unknown IDs are rejected", async () => {
  const client = new CursorCloudClient({ fetchImpl: async () =>
    ({ ok: false, status: 410 }) });
  const stream = client.streamRun("key-alice-123456789", agent, run);
  await assert.rejects(async () => {
    for await (const event of stream) void event;
  }, /stream expired/);
  await assert.rejects(async () => {
    for await (const event of client.streamRun("key-alice-123456789", agent, run,
      { lastEventId: "bad\r\nInjected-Header:foo" })) void event;
  }, /Invalid Cursor event cursor/);
});
