import test from "node:test";
import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { ControlPlane } from "../apps/control-plane/src/core.mjs";
import { ProjectHub } from "../apps/control-plane/src/project-hub.mjs";
import { normalizeCodexLocalSessions, readCodexLocalSessions } from "../apps/gateway/src/codex-local.mjs";

const thread = (id, cwd, preview, updatedAt = 1794500000) => ({
  id, cwd, preview, createdAt: 1794400000, updatedAt,
  modelProvider: "openai", status: { type: "notLoaded" },
});
test("Codex app-server result groups real CLI sessions by exact working folder", () => {
  const sessions = normalizeCodexLocalSessions({ data: [
    thread("11111111-2222-4333-8444-555555555555", "C:\\Users\\ASUS\\Projects\\Store", "Build the shop"),
    thread("aaaaaaa1-2222-4333-8444-555555555555", "C:\\Users\\ASUS\\Projects\\Store", "Add checkout"),
    thread("bbbbbbb1-2222-4333-8444-555555555555", "C:\\Users\\ASUS\\Projects\\O-AGENT-", "Fix Flutter"),
  ]});
  assert.equal(sessions.length, 3);
  assert.equal(sessions[0].state, "notLoaded");
  assert.equal(sessions[0].modelProvider, "openai");
  assert.equal(sessions[0].title, "Build the shop");
  const core = new ControlPlane({}, () => {});
  core.registerWorker({ id: "my-laptop", name: "OM-V16" });
  const hub = new ProjectHub(core, {}, { env: { OAGENT_ENABLE_CODEX_LOCAL_SYNC: "1" } });
  const result = hub.publishCodexLocal("my-laptop", { sessions });
  assert.equal(result.sessionCount, 3);
  assert.equal(result.projectCount, 2);
  assert.equal(hub.sources().find(x => x.id === "codex_cli").status, "connected");
  assert.ok(hub.sources().find(x => x.id === "codex_cli").capabilities.includes("view_session_metadata"));
});
test("Codex CLI sessions aren't fabricated active, and stale + empty sync are honest", async () => {
  let time = 100000;
  const core = new ControlPlane({}, () => {}, () => time);
  core.registerWorker({ id: "worker", name: "Work PC" });
  const hub = new ProjectHub(core, {}, { env: { OAGENT_ENABLE_CODEX_LOCAL_SYNC: "1" }, now: () => time });
  const input = normalizeCodexLocalSessions({ data: [
    thread("11111111-2222-4333-8444-555555555555", "C:\\Users\\ASUS\\Projects\\Store", "Build site"),
  ]});
  hub.publishCodexLocal("worker", { sessions: input });
  const first = (await hub.list()).projects[0];
  assert.equal(first.state, "history_available", "notLoaded is not an assertion the external Codex process stopped");
  assert.equal(first.source, "codex_cli");
  assert.equal(first.title, "Store");
  const details = await hub.details(first.id);
  assert.equal(details.project.sessions[0].state, "notLoaded");
  assert.equal(details.project.sessions[0].title, "Build site");
  time += 121000;
  const stale = (await hub.list()).projects[0];
  assert.equal(stale.state, "stale");
  assert.equal(hub.sources().find(x => x.id === "codex_cli").status, "configured_unverified");
  hub.publishCodexLocal("worker", { sessions: [] });
  const cleared = await hub.list();
  assert.equal(cleared.projects.length, 0);
  assert.equal(cleared.sources.find(x => x.id === "codex_cli").status, "connected");
});
test("Codex CLI local discovery requires explicit opt-in and authentic worker", () => {
  const core = new ControlPlane({}, () => {});
  const disabled = new ProjectHub(core, {}, { env: {} });
  core.registerWorker({ id: "my-laptop", name: "OM-V16" });
  assert.throws(() => disabled.publishCodexLocal("my-laptop", { sessions: [] }), /disabled/);
  const hub = new ProjectHub(core, {}, { env: { OAGENT_ENABLE_CODEX_LOCAL_SYNC: "1" } });
  assert.throws(() => hub.publishCodexLocal("missing-worker", { sessions: [] }), /Unknown worker/);
  assert.throws(() => hub.publishCodexLocal("my-laptop", { sessions: [
    { id: "11111111-2222-4333-8444-555555555555", cwd: "relative/path" },
  ] }), /absolute/);
});
test("Local Codex session parser filters malformed and duplicate records, bounds output", () => {
  const first = thread("11111111-2222-4333-8444-555555555555", "C:\\Users\\ASUS\\Project", "One");
  const parsed = normalizeCodexLocalSessions({ data: [
    first, first, { id: "bad", cwd: "C:\\ok" }, {}, ...Array.from({ length: 100 }, (_, i) => thread(
      "22222222-3333-4444-8555-" + String(i).padStart(12, "0"),
      "C:\\Projects\\p" + i, "Session " + i)),
  ] });
  assert.equal(parsed.length, 80);
  assert.throws(() => normalizeCodexLocalSessions({ tasks: [] }), /Expected/);
});
test("Official Codex JSON-RPC handshake reads local threads without requesting provider secrets", async () => {
  const requests = [];
  const factory = (bin, args, options) => {
    assert.ok(["codex", "powershell.exe"].includes(bin));
    assert.ok(args.join(" ").includes("app-server"));
    assert.equal(options.env.OAGENT_API_TOKEN, undefined);
    assert.equal(options.env.OAGENT_WORKER_TOKEN, undefined);
    assert.equal(options.env.OPENAI_API_KEY, undefined);
    const process = new EventEmitter();
    process.stdout = new EventEmitter();
    process.stderr = new EventEmitter();
    process.kill = () => true;
    process.stdin = {
      write(line) {
        const message = JSON.parse(line);
        requests.push(message);
        if (message.id === 1) queueMicrotask(() =>
          process.stdout.emit("data", Buffer.from(JSON.stringify({ id: 1, result: { userAgent: "codex" } }) + "\n")));
        if (message.id === 2) queueMicrotask(() =>
          process.stdout.emit("data", Buffer.from(JSON.stringify({ id: 2, result: {
            data: [thread("11111111-2222-4333-8444-555555555555", "C:\\Projects\\Agent", "Real work")],
            nextCursor: null,
          } }) + "\n")));
      }, end() {},
    };
    return process;
  };
  const sessions = await readCodexLocalSessions({
    spawnImpl: factory,
    isWindows: true,
    env: { OAGENT_API_TOKEN: "secret", OAGENT_WORKER_TOKEN: "worker-secret", OPENAI_API_KEY: "provider-secret" },
  });
  assert.equal(sessions.length, 1);
  assert.equal(sessions[0].title, "Real work");
  assert.equal(requests[0].method, "initialize");
  assert.equal(requests[1].method, "initialized");
  assert.equal(requests[2].method, "thread/list");
  assert.equal(requests[2].params.currentAccountOnly, true);
  assert.equal(requests[2].params.sortKey, "updated_at");
});

test("opting out drops stored working paths and session previews from persisted backend", async () => {
  let persisted = null;
  const core = new ControlPlane({}, data => { persisted = JSON.parse(JSON.stringify(data)); });
  core.registerWorker({ id: "laptop", name: "OM-V16" });
  const on = new ProjectHub(core, {}, { env: { OAGENT_ENABLE_CODEX_LOCAL_SYNC: "1" } });
  on.publishCodexLocal("laptop", { sessions: normalizeCodexLocalSessions({
    data: [thread("11111111-2222-4333-8444-555555555555",
      "C:\\Private\\Work", "Private session preview")],
  }) });
  assert.match(JSON.stringify(core.data.codexLocalProjects), /Private session preview/);
  const off = new ProjectHub(core, {}, { env: {} });
  assert.equal((await off.list()).projects.length, 0);
  assert.equal(Object.keys(persisted.codexLocalProjects).length, 0);
  assert.equal(Object.keys(persisted.codexLocalSync).length, 0);
});
