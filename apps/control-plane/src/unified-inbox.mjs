/** O-AGENT-owned approval inbox. No provider website polling or imagined approvals. */
const TITLES = Object.freeze({
  workspace_inventory: "Workspace inventory",
  codex_cli_turn: "Codex CLI",
  codex_cloud_submit: "Codex Cloud submission",
  claude_agent_turn: "Claude Agent SDK",
  copilot_sdk_turn: "GitHub Copilot SDK",
  vscode_open_file: "VS Code file request",
});
const text = (value, max) =>
  typeof value === "string" ? value.slice(0, max) : "";
const toDate = value =>
  Number.isFinite(value) && value >= 0 ? value : null;

function describeTask(task) {
  const p = task.parameters ?? {};
  if (task.kind === "workspace_inventory") return "Inspect enrolled workspace filenames";
  if (task.kind === "vscode_open_file")
    return "Open workspace file: " + text(p.relativePath, 350);
  return text(p.prompt, 4000);
}

/**
 * Only genuine tasks held by the owner's control plane and unexpired,
 * worker-authenticated permission requests enter the inbox. This is a
 * presentation/read model; it never authorizes actions. Every decision
 * is revalidated by the owner-only task/approval endpoints.
 */
export function buildOwnerApprovalInbox(snapshot, now, maxItems = 60) {
  const tasks = Array.isArray(snapshot?.tasks) ? snapshot.tasks : [];
  const workers = Array.isArray(snapshot?.workers) ? snapshot.workers : [];
  const workerState = new Map(workers.map(worker => [worker.id, worker.status]));
  const all = [];
  let expired = 0;
  for (const task of tasks) {
    if (!task || !Object.hasOwn(TITLES, task.kind) ||
        typeof task.id !== "string" || typeof task.workerId !== "string") continue;
    const workerOnline = workerState.get(task.workerId) === "online";
    const base = {
      taskId: task.id, taskKind: task.kind, provider: TITLES[task.kind],
      workerId: task.workerId,
      workerOnline,
      actionable: workerOnline,
      target: text(task.parameters?.cwd ?? task.parameters?.relativePath ??
        task.parameters?.environmentId, 600),
      permissionMode: text(task.parameters?.mode, 30) || null,
    };
    if (task.status === "waiting_for_approval") {
      all.push({
        ...base, actionKind: "task", approvalId: null,
        description: describeTask(task),
        requestedAt: toDate(task.createdAt), expiresAt: null,
      });
    }
    if (task.status !== "running") continue;
    for (const approval of Object.values(task.approvals ?? {})) {
      if (approval?.state !== "pending" ||
          typeof approval.id !== "string" ||
          !/^[A-Za-z0-9_-]{8,80}$/.test(approval.id)) continue;
      if (!Number.isFinite(approval.expiresAt) || approval.expiresAt <= now) {
        expired++;
        continue;
      }
      all.push({
        ...base, actionKind: "tool", approvalId: approval.id,
        description: text(approval.description, 1200),
        requestedAt: toDate(approval.requestedAt),
        expiresAt: approval.expiresAt,
      });
    }
  }
  all.sort((a, b) => (b.requestedAt ?? 0) - (a.requestedAt ?? 0) ||
    a.taskId.localeCompare(b.taskId));
  const limit = Number.isSafeInteger(maxItems)
    ? Math.min(80, Math.max(1, maxItems)) : 60;
  return {items: all.slice(0, limit), total: all.length,
    hasMore: all.length > limit, expired};
}
