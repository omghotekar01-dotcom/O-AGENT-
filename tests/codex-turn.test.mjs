import test from "node:test";
import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { ControlPlane, DomainError } from "../apps/control-plane/src/core.mjs";
import { ProjectHub } from "../apps/control-plane/src/project-hub.mjs";
import { runCodexTurn } from "../apps/gateway/src/codex-turn.mjs";

const sessionId = "11111111-2222-4333-8444-555555555555";
const cwd = "C:\\Projects\\RealCodex";
function setup() {
  let time = 1794500000000;
  const core = new ControlPlane({}, () => {}, () => time);
  core.registerWorker({ id: "my-laptop", name: "OM-V16" });
  const hub = new ProjectHub(core, {}, {
    env: { OAGENT_ENABLE_CODEX_LOCAL_SYNC: "1" }, now: () => time,
  });
  hub.publishCodexLocal("my-laptop", {
    sessions: [{ id: sessionId, cwd, title: "Fix project bugs", state: "notLoaded",
      updatedAt: "2026-11-12T15:00:00Z" }],
  });
  const id = Object.values(core.data.codexLocalProjects)[0].id;
  return { core, hub, id, setTime: x => time = x };
}
function submit(hub, id, mode = "read_only", requestKey = "codex-local-test-0123") {
  return hub.requestLocalCodexTurn({
    projectId: id, sessionId, prompt: "Summarize the actual project files", mode,
  }, requestKey);
}
test("real Codex turn must be bound to a signed-in worker, saved session and confirmed folder", () => {
  const { core, hub, id } = setup();
  assert.throws(() => hub.requestLocalCodexTurn({
    projectId: id, sessionId: "unknown-session-999", prompt: "Hello",
  }, "key-other-session-111"), /Session does not belong/);
  const task = submit(hub, id);
  assert.equal(task.status, "waiting_for_approval");
  assert.equal(task.parameters.cwd, cwd);
  assert.equal(task.parameters.mode, "read_only");
  assert.equal(core.claim("my-laptop"), null);
  assert.throws(() => hub.requestLocalCodexTurn({
    projectId: id, sessionId, prompt: "DIFFERENT",
  }, "other-key-0123456"), /already active/);
  const same = submit(hub, id);
  assert.equal(same.id, task.id);
  core.decide(task.id, true);
  assert.equal(core.claim("my-laptop").id, task.id);
  assert.throws(() => core.appendTaskUpdate("another-worker", task.id, {
    type: "agent_delta", text: "Attempt to inject fake event",
  }), /Incorrect worker/);
  assert.equal(core.appendTaskUpdate("my-laptop", task.id, { type: "agent_delta", text: "Actual response" }).accepted, true);
  assert.equal(core.appendTaskUpdate("my-laptop", task.id, { type: "agent_delta", text: " " }).accepted, true);
  assert.throws(() => core.appendTaskUpdate("my-laptop", task.id,
    { type: "fake_finished", text: "Done" }), /Unsupported/);
  core.finish("my-laptop", task.id, { ok: true, result: {
    providerStatus: "completed", output: "Actual response",
  } });
  assert.equal(core.getTask(task.id).updates.length, 2);
  assert.equal(core.getTask(task.id).result.output, "Actual response");
});
test("Codex per-action permission is scoped, expires and defaults to denial", () => {
  const { core, hub, id, setTime } = setup();
  const task = submit(hub, id, "workspace_write");
  core.decide(task.id, true);
  core.claim("my-laptop");
  const a = core.requestCodexApproval("my-laptop", task.id, {
    id: "approval-123456789",
    kind: "command",
    description: "Run npm test in C:\\Projects\\RealCodex",
  });
  assert.equal(a.state, "pending");
  assert.equal(core.codexApprovalStatus("my-laptop", task.id, a.id).state, "pending");
  assert.throws(() => core.decideCodexApproval(task.id, a.id, "yes"), /boolean/);
  core.decideCodexApproval(task.id, a.id, true);
  assert.equal(core.codexApprovalStatus("my-laptop", task.id, a.id).state, "approved");
  assert.throws(() => core.decideCodexApproval(task.id, a.id, true), /no longer active/);
  const other = core.requestCodexApproval("my-laptop", task.id, {
    id: "approval-222222222", kind: "file_change", description: "Change src/a.ts",
  });
  setTime(a.expiresAt + 2000);
  assert.equal(core.codexApprovalStatus("my-laptop", task.id, other.id).state, "expired");
  assert.throws(() => core.decideCodexApproval(task.id, other.id, true), /no longer active/);
});
test("read-only mode forbids further escalation even if worker asks", () => {
  const { core, hub, id } = setup();
  const task = submit(hub, id);
  core.decide(task.id, true);
  core.claim("my-laptop");
  assert.throws(() => core.requestCodexApproval("my-laptop", task.id, {
    id: "approval-12345678", kind: "command", description: "Erase files",
  }), /Read-only/);
});
test("stale project cannot dispatch phone prompts to a mismatched session", () => {
  const { hub, id, setTime } = setup();
  setTime(1794500130000);
  assert.throws(() => submit(hub, id), /stale/);
});

function fakeCodexServer(permission = false) {
  const sent = [];
  const process = new EventEmitter();
  process.stdout = new EventEmitter();
  process.stderr = new EventEmitter();
  process.kill = () => true;
  let turnStarted = false;
  const respond = value => queueMicrotask(() =>
    process.stdout.emit("data", Buffer.from(JSON.stringify(value) + "\n")));
  process.stdin = {
    write(line) {
      const m = JSON.parse(line);
      sent.push(m);
      if (m.id === 1 && m.method === "initialize") respond({ id: 1, result: {} });
      if (m.id === 2 && m.method === "thread/resume") respond({ id: 2, result: { thread: { id: sessionId } } });
      if (m.id === 3 && m.method === "turn/start") {
        turnStarted = true;
        respond({ id: 3, result: { turn: { id: "turn-1234" } } });
        if (permission) respond({ id: 77, method: "item/commandExecution/requestApproval",
          params: { threadId: sessionId, reason: "Run npm test", command: "npm test", cwd } });
        else {
          respond({ method: "item/agentMessage/delta", params: { threadId: sessionId, delta: "Real " } });
          respond({ method: "item/agentMessage/delta", params: { threadId: sessionId, delta: "Codex answer." } });
          respond({ method: "turn/completed", params: {
            threadId: sessionId, turn: { id: "turn-1234", status: "completed" },
          } });
        }
      }
      if (m.id === 77 && !m.method) {
        respond({ method: "item/agentMessage/delta", params: { threadId: sessionId,
          delta: "Permission was " + m.result.decision } });
        respond({ method: "turn/completed", params: {
          threadId: sessionId, turn: { id: "turn-1234", status: "completed" },
        } });
      }
    },
    end() {},
  };
  return { process, sent, get turnStarted() { return turnStarted; } };
}
const makeTask = mode => ({ kind: "codex_cli_turn", parameters: {
  sessionId, cwd, prompt: "Summarize this repo", mode,
} });
test("official Codex app-server actually resumes, starts turn, emits real deltas and finishes", async () => {
  const fake = fakeCodexServer();
  const updates = [];
  const result = await runCodexTurn(makeTask("read_only"), {
    spawnImpl: (_, __, options) => {
      assert.equal(options.env.OAGENT_API_TOKEN, undefined);
      assert.equal(options.env.OPENAI_API_KEY, undefined);
      return fake.process;
    },
    realpathImpl: async () => cwd, isWindows: true,
    env: { OAGENT_API_TOKEN: "SECRET", OPENAI_API_KEY: "SECRET", PATH: "PATH" },
    sendUpdate: async event => { updates.push(event); },
    timeoutMs: 2500,
  });
  assert.equal(result.providerStatus, "completed");
  assert.equal(result.output, "Real Codex answer.");
  assert.ok(updates.some(e => e.type === "agent_delta" && e.text.includes("Real Codex")));
  // Regression: Codex CLI 0.167.2 rejects the legacy
  // sandboxPolicy.readOnly.access object with an invalid-request error.
  const start = fake.sent.find(m => m.method === "turn/start").params;
  assert.deepEqual(start.sandboxPolicy, { type: "readOnly", networkAccess: false });
  assert.equal(start.approvalPolicy, "on-request");
  assert.equal(start.cwd, cwd);
  assert.equal(fake.turnStarted, true);
});
test("live provider tool approval only accepts a real human decision", async () => {
  const fake = fakeCodexServer(true);
  const updates = [];
  const result = await runCodexTurn(makeTask("workspace_write"), {
    spawnImpl: () => fake.process, realpathImpl: async () => cwd, isWindows: true,
    sendUpdate: async e => updates.push(e),
    askPermission: async a => {
      assert.equal(a.kind, "command");
      assert.match(a.description, /npm test/);
      return false;
    },
    timeoutMs: 2500,
  });
  assert.equal(result.providerStatus, "completed");
  assert.equal(fake.sent.find(m => m.id === 77 && !m.method).result.decision, "decline");
  // Both readOnly.access and workspaceWrite.readOnlyAccess are obsolete.
  // Project edits remain restricted to the user-approved workspace root.
  const start = fake.sent.find(m => m.method === "turn/start").params;
  assert.deepEqual(start.sandboxPolicy, {
    type: "workspaceWrite", writableRoots: [cwd], networkAccess: false,
  });
  assert.ok(updates.some(e => e.type === "status" && e.text.includes("denied")));
});

test("Codex permission escalation is explicitly denied with protocol-correct empty grant", async () => {
  const sent = [];
  const process = new EventEmitter();
  process.stdout = new EventEmitter();
  process.stderr = new EventEmitter();
  process.kill = () => true;
  process.stdin = {
    write(line) {
      const msg = JSON.parse(line);
      sent.push(msg);
      const respond = value => queueMicrotask(() =>
        process.stdout.emit("data", Buffer.from(JSON.stringify(value) + "\n")));
      if (msg.id === 1 && msg.method === "initialize") respond({ id: 1, result: {} });
      else if (msg.id === 2) respond({ id: 2, result: { thread: { id: sessionId } } });
      else if (msg.id === 3) {
        respond({ id: 3, result: { turn: { id: "turn-escalation" } } });
        respond({ id: 79, method: "item/permissions/requestApproval",
          params: { threadId: sessionId, reason: "Request extra network/filesystem rights" } });
      } else if (msg.id === 79 && msg.result) {
        respond({ method: "turn/completed", params: { threadId: sessionId,
          turn: { id: "turn-escalation", status: "completed" } } });
      }
    },
    end() {},
  };
  const updates = [];
  const result = await runCodexTurn(makeTask("workspace_write"), {
    spawnImpl: () => process, isWindows: true, realpathImpl: async () => cwd,
    sendUpdate: async x => updates.push(x),
    askPermission: async () => { throw Error("Must not ask human to grant unscoped permissions"); },
    timeoutMs: 2500,
  });
  assert.equal(result.providerStatus, "completed");
  assert.deepEqual(sent.find(m => m.id === 79 && !m.method)?.result,
    { permissions: {}, scope: "turn" });
  assert.ok(updates.some(e => e.type === "status" && e.text.includes("denied")));
});
