import { hostname, platform, arch, cpus, totalmem, freemem, uptime } from "node:os";
import { readdir, lstat, realpath } from "node:fs/promises";
import { resolve, basename, join } from "node:path";
import { readCodexCloudTasks, submitCodexCloudTask } from "./codex-cloud.mjs";
import { readCodexLocalSessions } from "./codex-local.mjs";
import { runCodexTurn } from "./codex-turn.mjs";
import { runProviderTurn } from "./provider-turn.mjs";

const endpoint = new URL(process.env.OAGENT_SERVER_URL || "http://127.0.0.1:8787");
if (endpoint.protocol !== "https:" && !(endpoint.protocol === "http:" && ["127.0.0.1", "localhost", "::1"].includes(endpoint.hostname))) {
  throw new Error("Worker requires HTTPS except for localhost development");
}
const token = process.env.OAGENT_WORKER_TOKEN ?? "";
if (token.length < 24) throw new Error("OAGENT_WORKER_TOKEN must be at least 24 characters");
const id = process.env.OAGENT_WORKER_ID || "local-worker";
const root = resolve(process.env.OAGENT_WORKSPACE_ROOT || process.cwd());
if (!/^[a-zA-Z0-9_-]+$/.test(id)) throw new Error("Invalid OAGENT_WORKER_ID");
const sleep = ms => new Promise(r => setTimeout(r, ms));
const capabilities = [
  "system_info", "workspace_inventory",
  ...(process.env.OAGENT_ENABLE_CODEX_CLOUD_SYNC === "1" ? ["codex_cloud_submit"] : []),
  ...(process.env.OAGENT_ENABLE_CODEX_LOCAL_SYNC === "1" ? ["codex_cli_turn"] : []),
  ...(process.env.OAGENT_ENABLE_CLAUDE_AGENT_SDK === "1" ? ["claude_agent_turn"] : []),
  ...(process.env.OAGENT_ENABLE_COPILOT_SDK === "1" ? ["copilot_sdk_turn"] : []),
];


async function api(path, body = {}, method = "POST") {
  const result = await fetch(new URL(path, endpoint), {
    method,
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: method === "GET" ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(15000),
  });
  const json = await result.json();
  if (!result.ok) throw new Error(json.error || `HTTP ${result.status}`);
  return json;
}
async function execute(task) {
  if (task.kind === "system_info") {
    return { hostname: hostname(), platform: platform(), architecture: arch(), cpuCount: cpus().length, totalMemoryBytes: totalmem(), freeMemoryBytes: freemem(), uptimeSeconds: Math.floor(uptime()), at: new Date().toISOString() };
  }
  if (task.kind === "workspace_inventory") {
    const safeRoot = await realpath(root);
    const entries = (await readdir(safeRoot)).slice(0, 100);
    const files = [];
    for (const name of entries) {
      const stat = await lstat(join(safeRoot, name));
      files.push({ name: basename(name), type: stat.isSymbolicLink() ? "symlink" : stat.isDirectory() ? "directory" : stat.isFile() ? "file" : "other", sizeBytes: stat.isFile() ? stat.size : null });
    }
    return { root: safeRoot, entries: files, truncated: (await readdir(safeRoot)).length > files.length };
  }
  if (task.kind === "codex_cloud_submit") {
    if (process.env.OAGENT_ENABLE_CODEX_CLOUD_SYNC !== "1") throw new Error("Codex Cloud connector is not enabled");
    if (!task.parameters || typeof task.parameters !== "object") throw new Error("Missing approved task parameters");
    // Only runs AFTER the operator has approved the exact immutable task.
    return submitCodexCloudTask(task.parameters.environmentId, task.parameters.prompt);
  }
  if (task.kind === "claude_agent_turn" || task.kind === "copilot_sdk_turn") {
    return runProviderTurn(task, {
      sendUpdate: event => api("/api/workers/" + id + "/tasks/" + task.id + "/update", event),
      askPermission: async request => {
        await api("/api/workers/" + id + "/tasks/" + task.id + "/approvals", request);
        const expires = Date.now() + 180000;
        while (Date.now() < expires) {
          await sleep(1800);
          try {
            const result = await api("/api/workers/" + id + "/tasks/" +
              task.id + "/approvals/" + request.id, {}, "GET");
            if (result.state === "approved") return true;
            if (result.state === "denied" || result.state === "expired") return false;
          } catch { return false; }
        }
        return false;
      },
    });
  }
  if (task.kind === "codex_cli_turn") {
    if (process.env.OAGENT_ENABLE_CODEX_LOCAL_SYNC !== "1") throw new Error("Codex CLI session control is disabled");
    return runCodexTurn(task, {
      sendUpdate: event => api(`/api/workers/${id}/tasks/${task.id}/update`, event),
      askPermission: async request => {
        // A real Codex request is tied to the specific live turn.
        // No acceptance without an authenticated phone decision.
        await api(`/api/workers/${id}/tasks/${task.id}/approvals`, request);
        const expires = Date.now() + 180000;
        while (Date.now() < expires) {
          await sleep(1800);
          try {
            const { state } = await api(
              `/api/workers/${id}/tasks/${task.id}/approvals/${request.id}`, {}, "GET");
            if (state === "approved") return true;
            if (state === "denied" || state === "expired") return false;
          } catch { return false; }
        }
        return false;
      },
    });
  }
  throw new Error("Unsupported task");
}
async function main() {
  console.log(`O-AGENT worker ${id} starting; workspace root: ${root}`);
  let lastCodexSync = 0;
  let lastLocalCodexSync = 0;
  let activeTask = false;
  await api("/api/workers/register", { id, name: hostname(), capabilities });
  while (true) {
    try {
      // Provider history queries can take 25-30 seconds. Run them off the
      // heartbeat/task-claim loop so a slow CLI never makes the worker appear
      // offline or delays human-approved tasks.
      if (process.env.OAGENT_ENABLE_CODEX_LOCAL_SYNC === "1" && Date.now() - lastLocalCodexSync > 45000) {
        lastLocalCodexSync = Date.now();
        void (async () => {
          try {
            const sessions = await readCodexLocalSessions();
            await api(`/api/workers/${id}/codex/local/sync`, { sessions });
          } catch {
            console.error("Local Codex CLI sessions unavailable; check Codex app-server support and signed-in Windows user.");
          }
        })();
      }
      if (process.env.OAGENT_ENABLE_CODEX_CLOUD_SYNC === "1" && Date.now() - lastCodexSync > 45000) {
        lastCodexSync = Date.now();
        void (async () => {
          try {
            const tasks = await readCodexCloudTasks();
            await api(`/api/workers/${id}/codex/sync`, { tasks });
          } catch {
            // Never leak CLI output, browser cookies, provider sessions or credentials in logs.
            console.error("Codex Cloud sync unavailable; check Codex CLI installation and login.");
          }
        })();
      }
      await api(`/api/workers/${id}/heartbeat`);
      if (!activeTask) {
        const { task } = await api(`/api/workers/${id}/next`);
        if (task) {
          activeTask = true;
          // A long-running Codex turn must not block heartbeats or provider
          // metadata synchronization. Only one active approved task per worker.
          void (async () => {
            try {
              const result = await execute(task);
              if (["codex_cli_turn","claude_agent_turn","copilot_sdk_turn"].includes(task.kind) &&
                  result.providerStatus !== "completed") {
                await api(`/api/workers/${id}/tasks/${task.id}/finish`,
                  { ok: false, error: "Codex turn ended with provider status: " + result.providerStatus });
              } else {
                await api(`/api/workers/${id}/tasks/${task.id}/finish`, { ok: true, result });
              }
            } catch (err) {
              try {
                await api(`/api/workers/${id}/tasks/${task.id}/finish`,
                  { ok: false, error: String(err.message).slice(0, 1000) });
              } catch { console.error("Could not report completed task state; check backend connectivity."); }
            } finally { activeTask = false; }
          })();
        }
      }
    } catch (err) {
      console.error("Worker polling error:", err.message);
      try { await api("/api/workers/register", { id, name: hostname(), capabilities }); } catch { /* retry next cycle */ }
    }
    await sleep(3000);
  }
}
main().catch(err => { console.error(err.message); process.exitCode = 1; });
