import { randomUUID } from "node:crypto";

const TASK_TYPES = new Set(["system_info", "workspace_inventory"]);
const TERMINAL = new Set(["completed", "failed", "cancelled", "interrupted", "rejected"]);
const MAX_EVENTS = 5000;
export class DomainError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}
function requiredString(value, field, max = 120) {
  if (typeof value !== "string" || value.trim().length < 1 || value.length > max) {
    throw new DomainError(400, `Invalid ${field}`);
  }
  return value.trim();
}
export class ControlPlane {
  constructor(initial = {}, persist = () => {}, clock = () => Date.now()) {
    this.data = {
      workers: initial.workers ?? {},
      tasks: initial.tasks ?? {},
      events: initial.events ?? [],
      sequence: initial.sequence ?? 0,
      agentThreads: initial.agentThreads ?? {},
      projects: initial.projects ?? {},
      externalProjects: initial.externalProjects ?? {},
    };
    this.persist = persist;
    this.clock = clock;
    this.subscribers = new Set();
  }
  commit(type, detail = {}) {
    const event = { sequence: ++this.data.sequence, id: randomUUID(), type, at: new Date(this.clock()).toISOString(), ...detail };
    this.data.events.push(event);
    if (this.data.events.length > MAX_EVENTS) this.data.events.splice(0, this.data.events.length - MAX_EVENTS);
    this.persist(this.data);
    for (const fn of this.subscribers) fn(event);
    return event;
  }
  subscribe(fn) { this.subscribers.add(fn); return () => this.subscribers.delete(fn); }
  registerWorker(body) {
    const id = requiredString(body.id, "worker ID", 100);
    if (!/^[a-zA-Z0-9_-]+$/.test(id)) throw new DomainError(400, "Invalid worker ID format");
    const name = requiredString(body.name, "worker name");
    const now = this.clock();
    const existing = this.data.workers[id];
    this.data.workers[id] = { id, name, capabilities: [...TASK_TYPES], registeredAt: existing?.registeredAt ?? now, lastSeenAt: now };
    this.commit("machine.online", { workerId: id });
    return this.data.workers[id];
  }
  heartbeat(id) {
    const worker = this.data.workers[id];
    if (!worker) throw new DomainError(404, "Unknown worker");
    worker.lastSeenAt = this.clock();
    this.commit("agent.heartbeat", { workerId: id });
    return { status: "ok" };
  }
  createTask(body, requestKey) {
    const workerId = requiredString(body.workerId, "workerId", 100);
    const kind = requiredString(body.kind, "kind", 60);
    if (!TASK_TYPES.has(kind)) throw new DomainError(400, "Unsupported task capability");
    if (!this.data.workers[workerId]) throw new DomainError(404, "Worker is not registered");
    const key = requiredString(requestKey, "Idempotency-Key", 200);
    if (key.length < 12) throw new DomainError(400, "Idempotency-Key must be at least 12 characters");
    const existing = Object.values(this.data.tasks).find(t => t.requestKey === key);
    if (existing) {
      if (existing.workerId !== workerId || existing.kind !== kind) throw new DomainError(409, "Idempotency key reused for different task");
      return existing;
    }
    const task = {
      id: randomUUID(), requestKey: key, workerId, kind, status: kind === "workspace_inventory" ? "waiting_for_approval" : "queued",
      createdAt: this.clock(), updatedAt: this.clock(), result: null, error: null,
    };
    this.data.tasks[task.id] = task;
    this.commit("task.created", { taskId: task.id, workerId, kind });
    this.commit(task.status === "queued" ? "task.queued" : "task.waiting_for_approval", { taskId: task.id, workerId });
    return task;
  }
  decide(id, approve) {
    const task = this.getTask(id);
    if (task.status !== "waiting_for_approval") throw new DomainError(409, "Task does not require approval");
    task.status = approve ? "queued" : "rejected";
    task.updatedAt = this.clock();
    this.commit(approve ? "task.approved" : "task.rejected", { taskId: id, workerId: task.workerId });
    return task;
  }
  claim(workerId) {
    const worker = this.data.workers[workerId];
    if (!worker) throw new DomainError(404, "Unknown worker");
    if (this.clock() - worker.lastSeenAt > 30000) throw new DomainError(409, "Worker heartbeat expired");
    const task = Object.values(this.data.tasks).find(t => t.workerId === workerId && t.status === "queued");
    if (!task) return null;
    task.status = "running"; task.updatedAt = this.clock();
    this.commit("task.started", { taskId: task.id, workerId });
    return task;
  }
  finish(workerId, taskId, body) {
    const task = this.getTask(taskId);
    if (task.workerId !== workerId) throw new DomainError(403, "Task assigned to a different worker");
    if (task.status !== "running") throw new DomainError(409, "Task not running");
    if (body.ok !== true && body.ok !== false) throw new DomainError(400, "ok must be boolean");
    if (body.ok) {
      const result = JSON.stringify(body.result ?? {});
      if (result.length > 20000) throw new DomainError(413, "Result too large");
      task.result = JSON.parse(result); task.status = "completed";
    } else {
      task.error = requiredString(body.error, "error", 1000); task.status = "failed";
    }
    task.updatedAt = this.clock();
    this.commit(body.ok ? "task.completed" : "task.failed", { taskId, workerId });
    return task;
  }
  cancel(id) {
    const task = this.getTask(id);
    if (TERMINAL.has(task.status)) throw new DomainError(409, "Task already terminal");
    if (task.status === "running") throw new DomainError(409, "Running-task cancellation requires runtime support");
    task.status = "cancelled"; task.updatedAt = this.clock();
    this.commit("task.cancelled", { taskId: id, workerId: task.workerId });
    return task;
  }
  getTask(id) {
    const task = this.data.tasks[id];
    if (!task) throw new DomainError(404, "Unknown task");
    return task;
  }
  snapshot() {
    const now = this.clock();
    return {
      workers: Object.values(this.data.workers).map(w => ({ ...w, status: now - w.lastSeenAt <= 30000 ? "online" : "offline" })),
      tasks: Object.values(this.data.tasks).sort((a, b) => b.createdAt - a.createdAt),
      nextSequence: this.data.sequence + 1,
    };
  }
  events(after = 0) { return this.data.events.filter(e => e.sequence > after).slice(0, 200); }
}
