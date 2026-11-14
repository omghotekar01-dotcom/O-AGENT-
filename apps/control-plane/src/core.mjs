import { randomUUID } from "node:crypto";

const TASK_TYPES = new Set(["system_info", "workspace_inventory", "codex_cloud_submit", "codex_cli_turn", "codex_cli_history", "claude_agent_turn", "copilot_sdk_turn", "vscode_open_file"]);
const TERMINAL = new Set(["completed", "failed", "cancelled", "interrupted", "rejected"]);
const MAX_EVENTS = 5000;
const HISTORY_PREVIEW_TTL = 30 * 60 * 1000;
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
      codexLocalProjects: initial.codexLocalProjects ?? {},
      codexLocalSync: initial.codexLocalSync ?? {},
      accounts: initial.accounts ?? {},
    };
    this.persist = persist;
    this.clock = clock;
    this.subscribers = new Set();
    // Full saved Codex messages are deliberately NOT part of persistent
    // tasks/events. A temporary in-memory preview expires automatically.
    this.historyPreviews = new Map();
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
    const declared = Array.isArray(body.capabilities) ? body.capabilities : [
      "system_info", "workspace_inventory", "codex_cloud_submit", "codex_cli_turn", "codex_cli_history",
    ];
    if (declared.length > 8 || declared.some(c => typeof c !== "string" || !TASK_TYPES.has(c)))
      throw new DomainError(400, "Invalid worker capabilities");
    const capabilities = [...new Set(declared)];
    this.data.workers[id] = { id, name, capabilities, registeredAt: existing?.registeredAt ?? now, lastSeenAt: now };
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
    if (!this.data.workers[workerId].capabilities?.includes(kind))
      throw new DomainError(409, "This worker has not enrolled the requested capability");
    let parameters = null;
    if (kind === "codex_cloud_submit") {
      const environmentId = requiredString(body.environmentId, "Codex Cloud environmentId", 120);
      if (!/^[A-Za-z0-9_-]{3,120}$/.test(environmentId)) throw new DomainError(400, "Invalid Codex Cloud environmentId");
      const prompt = requiredString(body.prompt, "Codex Cloud prompt", 2000);
      parameters = { environmentId, prompt };
    }
    if (kind === "codex_cli_history") {
      const projectId = requiredString(body.projectId, "Codex projectId", 160);
      const sessionId = requiredString(body.sessionId, "Codex conversation ID", 120);
      if (!/^[a-zA-Z0-9_-]{8,120}$/.test(sessionId))
        throw new DomainError(400, "Invalid Codex conversation ID");
      parameters = { projectId, sessionId };
    }
    if (kind === "codex_cli_turn") {
      const projectId = requiredString(body.projectId, "Codex projectId", 160);
      const sessionId = requiredString(body.sessionId, "Codex sessionId", 120);
      if (!/^[a-zA-Z0-9_-]{8,120}$/.test(sessionId)) throw new DomainError(400, "Invalid Codex sessionId");
      const cwd = requiredString(body.cwd, "Codex working folder", 600);
      const prompt = requiredString(body.prompt, "Codex prompt", 4000);
      const mode = body.mode || "read_only";
      if (!["read_only", "workspace_write"].includes(mode)) throw new DomainError(400, "Invalid Codex execution mode");
      parameters = { projectId, sessionId, cwd, prompt, mode };
    }
    if (["claude_agent_turn", "copilot_sdk_turn"].includes(kind)) {
      const cwd = requiredString(body.cwd, "enrolled workspace folder", 600);
      if (!/^(?:[A-Za-z]:[\\/]|\/)/.test(cwd) || /[\x00-\x1f]/.test(cwd))
        throw new DomainError(400, "Expected absolute workspace path");
      const prompt = requiredString(body.prompt, "agent instruction", 4000);
      const mode = body.mode ?? "read_only";
      if (!["read_only", "workspace_write"].includes(mode))
        throw new DomainError(400, "Invalid provider permission mode");
      const sessionId = body.sessionId ?? null;
      if (sessionId != null && (typeof sessionId !== "string" ||
          !/^[a-zA-Z0-9_-]{8,120}$/.test(sessionId)))
        throw new DomainError(400, "Invalid SDK session ID");
      if (sessionId != null) {
        const knownSession = Object.values(this.data.tasks).find(t =>
          t.kind === kind && t.status === "completed" &&
          t.result?.sessionId === sessionId);
        if (knownSession &&
            (knownSession.workerId !== workerId ||
             knownSession.parameters?.cwd !== cwd))
          throw new DomainError(409,
            "This SDK session belongs to a different enrolled worker or workspace");
        if (this.clock() - this.data.workers[workerId].lastSeenAt > 30000)
          throw new DomainError(409,
            "The original SDK session worker is offline. Reconnect it before resuming.");
      }
      parameters = { cwd, prompt, mode, sessionId };
    }
    if (kind === "vscode_open_file") {
      const relativePath = requiredString(body.relativePath, "relative file path", 350);
      if (relativePath.startsWith("/") || /^[A-Za-z]:/.test(relativePath) ||
          relativePath.split(/[\\/]/).some(p => !p || p === "." || p === "..") ||
          /[\x00-\x1f]/.test(relativePath)) {
        throw new DomainError(400, "Open file path must be relative to the enrolled VS Code workspace");
      }
      parameters = { relativePath };
    }
    const key = requiredString(requestKey, "Idempotency-Key", 200);
    if (key.length < 12) throw new DomainError(400, "Idempotency-Key must be at least 12 characters");
    const existing = Object.values(this.data.tasks).find(t => t.requestKey === key);
    if (existing) {
      if (existing.workerId !== workerId || existing.kind !== kind || JSON.stringify(existing.parameters ?? null) !== JSON.stringify(parameters)) throw new DomainError(409, "Idempotency key reused for different task");
      return existing;
    }
    const task = {
      id: randomUUID(), requestKey: key, workerId, kind, parameters,
      status: ["workspace_inventory", "codex_cloud_submit", "codex_cli_turn", "claude_agent_turn", "copilot_sdk_turn", "vscode_open_file"].includes(kind) ? "waiting_for_approval" : "queued",
      updates: [], approvals: {},
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
      if (task.kind === "codex_cli_history") {
        const until = this.clock() + HISTORY_PREVIEW_TTL;
        for (const [key, value] of this.historyPreviews) {
          if (value.expiresAt <= this.clock()) this.historyPreviews.delete(key);
        }
        // Bound even fresh histories, so repeated chats cannot exhaust RAM.
        while (this.historyPreviews.size >= 24) {
          this.historyPreviews.delete(this.historyPreviews.keys().next().value);
        }
        this.historyPreviews.set(taskId, {
          expiresAt: until,
          result: JSON.parse(result),
        });
        // Persist only metadata, never a complete external conversation.
        task.result = { temporary: true, expiresAt: until };
      } else {
        task.result = JSON.parse(result);
      }
      task.status = "completed";
    } else {
      task.error = requiredString(body.error, "error", 1000); task.status = "failed";
    }
    task.updatedAt = this.clock();
    for (const approval of Object.values(task.approvals ?? {})) {
      if (approval.state === "pending") approval.state = "expired";
    }
    this.commit(body.ok ? "task.completed" : "task.failed", { taskId, workerId });
    return task;
  }
  appendTaskUpdate(workerId, taskId, body) {
    const task = this.getTask(taskId);
    if (task.workerId !== workerId) throw new DomainError(403, "Incorrect worker");
    if (!["codex_cli_turn", "claude_agent_turn", "copilot_sdk_turn"].includes(task.kind) || task.status !== "running") throw new DomainError(409, "Not a running supervised turn");
    const type = requiredString(body?.type, "event type", 60);
    const allowed = new Set(["session_resumed","turn_started","agent_delta","tool_started","tool_finished","turn_completed","error","status"]);
    if (!allowed.has(type)) throw new DomainError(400, "Unsupported Codex event type");
    if (body.text != null && (typeof body.text !== "string" || body.text.length > 2500)) throw new DomainError(400, "Invalid Codex event text");
    const text = body.text ?? "";
    if (task.updates.length >= 240) {
      // Bounded storage. Latest updates are still available for reconnect.
      task.updates.splice(0, task.updates.length - 239);
    }
    const event = { index: (task.nextUpdate ?? 0) + 1, type, text, at: new Date(this.clock()).toISOString() };
    task.nextUpdate = event.index;
    task.updates.push(event);
    task.updatedAt = this.clock();
    this.commit("codex.turn.event", { taskId, workerId, index: event.index, eventType: type });
    return { accepted: true, index: event.index };
  }
  requestCodexApproval(workerId, taskId, body) {
    const task = this.getTask(taskId);
    if (task.workerId !== workerId) throw new DomainError(403, "Incorrect worker");
    if (!["codex_cli_turn", "claude_agent_turn", "copilot_sdk_turn"].includes(task.kind) || task.status !== "running") throw new DomainError(409, "Not a running supervised turn");
    if (task.parameters?.mode === "read_only") throw new DomainError(403, "Read-only Codex turns cannot request permission escalation");
    if (Object.values(task.approvals ?? {}).filter(a => a.state === "pending").length > 3) throw new DomainError(429, "Too many pending approvals");
    const id = requiredString(body?.id, "approval ID", 80);
    if (!/^[a-zA-Z0-9_-]{8,80}$/.test(id)) throw new DomainError(400, "Invalid approval ID");
    const kind = requiredString(body?.kind, "approval kind", 64);
    if (!["command", "file_change", "permissions"].includes(kind)) throw new DomainError(400, "Unsupported approval kind");
    const description = requiredString(body?.description, "approval description", 1200);
    if (task.approvals?.[id]) throw new DomainError(409, "Approval already exists");
    const approval = {
      id, kind, description, state: "pending",
      requestedAt: this.clock(), expiresAt: this.clock() + 180000,
    };
    task.approvals[id] = approval;
    this.commit("codex.approval.requested", { taskId, workerId, approvalId: id, kind });
    return approval;
  }
  decideCodexApproval(taskId, approvalId, approve) {
    const task = this.getTask(taskId);
    const approval = task.approvals?.[approvalId];
    if (!approval) throw new DomainError(404, "Codex approval not found");
    if (task.status !== "running" || approval.state !== "pending" || this.clock() > approval.expiresAt) {
      if (approval.state === "pending") {
        approval.state = "expired";
        this.commit("codex.approval.expired", { taskId, approvalId });
      }
      throw new DomainError(409, "Approval is no longer active");
    }
    if (typeof approve !== "boolean") throw new DomainError(400, "approve must be boolean");
    if (approve && task.parameters?.mode === "read_only") throw new DomainError(403, "Read-only turn cannot approve escalation");
    approval.state = approve ? "approved" : "denied";
    approval.decidedAt = this.clock();
    this.commit(approve ? "codex.approval.approved" : "codex.approval.denied", { taskId, approvalId });
    return approval;
  }
  codexApprovalStatus(workerId, taskId, approvalId) {
    const task = this.getTask(taskId);
    if (task.workerId !== workerId) throw new DomainError(403, "Incorrect worker");
    const approval = task.approvals?.[approvalId];
    if (!approval) throw new DomainError(404, "Codex approval not found");
    if (task.status !== "running" || this.clock() > approval.expiresAt) {
      if (approval.state === "pending") {
        approval.state = "expired";
        this.commit("codex.approval.expired", { taskId, approvalId });
      }
    }
    return { state: approval.state };
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
    if (task.kind === "codex_cli_history" && task.status === "completed") {
      const preview = this.historyPreviews.get(id);
      if (preview && preview.expiresAt > this.clock()) {
        return { ...task, result: preview.result, historyExpired: false };
      }
      this.historyPreviews.delete(id);
      return { ...task, result: null, historyExpired: true };
    }
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
