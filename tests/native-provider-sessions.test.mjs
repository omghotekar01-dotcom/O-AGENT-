import test from "node:test";
import assert from "node:assert/strict";
import { ControlPlane } from "../apps/control-plane/src/core.mjs";
import { ProjectHub } from "../apps/control-plane/src/project-hub.mjs";

const workerId = "trusted-worker";
const sessionId = "provider_session_123456";

function createFixture() {
  let now = 1000000;
  const core = new ControlPlane({}, () => {}, () => now);
  core.registerWorker({id: workerId, name: "Private laptop",
    capabilities: ["claude_agent_turn", "copilot_sdk_turn"]});
  const hub = new ProjectHub(core, {status: () => ({configured: false})},
    {env: {}, now: () => now});
  let keyIndex = 0;
  function complete(kind, id = sessionId) {
    now += 1;
    const task = core.createTask({workerId, kind, cwd: "/workspace/example",
      prompt: "Continue actual task", mode: "read_only"},
      "native-resume-request-" + (++keyIndex));
    core.decide(task.id, true);
    assert.equal(core.claim(workerId)?.id, task.id);
    core.finish(workerId, task.id, {ok: true, result: {
      providerStatus: "completed", sessionId: id, response: "Done",
    }});
    return task;
  }
  return {core, hub, complete, advance: ms => { now += ms; }};
}

test("only real completed SDK results become resumable native sessions", () => {
  const f = createFixture();
  assert.deepEqual(f.hub.remoteOverview().nativeSessions, []);
  const completed = f.complete("claude_agent_turn");
  const native = f.hub.remoteOverview().nativeSessions;
  assert.equal(native.length, 1);
  assert.equal(native[0].sessionId, sessionId);
  assert.equal(native[0].lastRunId, completed.id);
  assert.equal(native[0].kind, "claude_agent_turn");
  assert.equal(native[0].workerId, workerId);
  assert.equal(native[0].cwd, "/workspace/example");
  assert.equal(native[0].resumeEligible, true);
  assert.equal("response" in native[0], false);
});

test("deduplicate SDK session ids by worker/provider and use newest run", () => {
  const f = createFixture();
  f.complete("claude_agent_turn");
  const latest = f.complete("claude_agent_turn");
  f.complete("copilot_sdk_turn");
  const records = f.hub.remoteOverview().nativeSessions;
  assert.equal(records.length, 2);
  assert.equal(records[1].lastRunId, latest.id);
  assert.equal(records[0].kind, "copilot_sdk_turn");
});

test("unverified or malformed SDK IDs and unapproved runs are not listed", () => {
  const f = createFixture();
  f.complete("claude_agent_turn", "in valid");
  const waiting = f.core.createTask({workerId, kind: "copilot_sdk_turn",
    cwd: "/workspace/example", prompt: "Waiting", mode: "read_only"},
    "pending-provider-session-123");
  assert.equal(waiting.status, "waiting_for_approval");
  assert.deepEqual(f.hub.remoteOverview().nativeSessions, []);
});

test("resume eligibility is tied to the original online enrolled worker", () => {
  const f = createFixture();
  f.complete("copilot_sdk_turn");
  f.advance(31000);
  const native = f.hub.remoteOverview().nativeSessions;
  assert.equal(native.length, 1);
  assert.equal(native[0].resumeEligible, false);
  assert.equal(f.hub.remoteOverview().machines[0].status, "offline");
});

test("known SDK sessions cannot be replayed on a different worker or workspace", () => {
  const f = createFixture();
  f.complete("claude_agent_turn");
  f.core.registerWorker({id: "other-worker", name: "Another machine",
    capabilities: ["claude_agent_turn"]});
  const request = {workerId, kind: "claude_agent_turn",
    cwd: "/workspace/example", prompt: "Continue safely", mode: "read_only",
    sessionId};
  assert.throws(() => f.core.createTask({...request, workerId: "other-worker"},
    "wrong-worker-session-12345"), /different enrolled worker/);
  assert.throws(() => f.core.createTask({...request, cwd: "/workspace/other"},
    "wrong-directory-session-12345"), /different enrolled worker/);
  f.advance(31000);
  assert.throws(() => f.core.createTask(request,
    "stale-worker-session-12345"), /worker is offline/);
});
