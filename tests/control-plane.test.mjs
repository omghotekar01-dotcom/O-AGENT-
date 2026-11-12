import test from "node:test";
import assert from "node:assert/strict";
import { ControlPlane, DomainError } from "../apps/control-plane/src/core.mjs";

function fixture() {
  let now = 100000;
  let saved = 0;
  const core = new ControlPlane({}, () => saved++, () => now);
  return { core, tick: ms => now += ms, get saves() { return saved; } };
}
test("registration, live state and real result lifecycle", () => {
  const f = fixture();
  assert.equal(f.core.snapshot().workers.length, 0);
  f.core.registerWorker({ id: "laptop_1", name: "Local laptop" });
  assert.equal(f.core.snapshot().workers[0].status, "online");
  const task = f.core.createTask({ workerId: "laptop_1", kind: "system_info" }, "unique-key-12345");
  assert.equal(task.status, "queued");
  assert.equal(f.core.claim("laptop_1").id, task.id);
  f.core.finish("laptop_1", task.id, { ok: true, result: { cpuCount: 8 } });
  assert.equal(f.core.getTask(task.id).status, "completed");
  assert.equal(f.core.getTask(task.id).result.cpuCount, 8);
  assert.ok(f.saves >= 4);
  assert.ok(f.core.events().some(e => e.type === "task.completed"));
});
test("approval must precede inventory execution", () => {
  const { core } = fixture();
  core.registerWorker({ id: "laptop", name: "Laptop" });
  const task = core.createTask({ workerId: "laptop", kind: "workspace_inventory" }, "approval-key-00001");
  assert.equal(task.status, "waiting_for_approval");
  assert.equal(core.claim("laptop"), null);
  core.decide(task.id, true);
  assert.equal(core.claim("laptop").status, "running");
  assert.throws(() => core.decide(task.id, false), e => e instanceof DomainError && e.status === 409);
});
test("rejected tasks are never executed", () => {
  const { core } = fixture();
  core.registerWorker({ id: "laptop", name: "Laptop" });
  const task = core.createTask({ workerId: "laptop", kind: "workspace_inventory" }, "approval-key-00002");
  core.decide(task.id, false);
  assert.equal(task.status, "rejected");
  assert.equal(core.claim("laptop"), null);
});
test("idempotency and unregistered worker checks", () => {
  const { core } = fixture();
  assert.throws(() => core.createTask({ workerId: "unknown", kind: "system_info" }, "unique-key-12345"), /not registered/);
  core.registerWorker({ id: "worker", name: "Worker" });
  const one = core.createTask({ workerId: "worker", kind: "system_info" }, "unique-key-12345");
  assert.equal(core.createTask({ workerId: "worker", kind: "system_info" }, "unique-key-12345").id, one.id);
  assert.throws(() => core.createTask({ workerId: "worker", kind: "workspace_inventory" }, "unique-key-12345"), /reused/);
});
test("expired worker and cross-worker result submission rejected", () => {
  const f = fixture();
  f.core.registerWorker({ id: "a", name: "A" });
  f.core.registerWorker({ id: "b", name: "B" });
  const task = f.core.createTask({ workerId: "a", kind: "system_info" }, "unique-key-54321");
  f.tick(31000);
  assert.equal(f.core.snapshot().workers[0].status, "offline");
  assert.throws(() => f.core.claim("a"), /expired/);
  f.core.heartbeat("a");
  f.core.claim("a");
  assert.throws(() => f.core.finish("b", task.id, { ok: true }), e => e.status === 403);
});
test("terminal state and event cursor protection", () => {
  const { core } = fixture();
  core.registerWorker({ id: "local", name: "Local" });
  const task = core.createTask({ workerId: "local", kind: "system_info" }, "unique-key-cancel");
  core.cancel(task.id);
  assert.throws(() => core.cancel(task.id), e => e.status === 409);
  assert.equal(core.claim("local"), null);
  const events = core.events(1);
  assert.ok(events.every(e => e.sequence > 1));
});
test("unsupported capabilities cannot enter queue", () => {
  const { core } = fixture();
  core.registerWorker({ id: "local", name: "Local" });
  assert.throws(() => core.createTask({ workerId: "local", kind: "shell_exec" }, "unique-key-shell"), e => e.status === 400);
});
