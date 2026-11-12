import { hostname, platform, arch, cpus, totalmem, freemem, uptime } from "node:os";
import { readdir, lstat, realpath } from "node:fs/promises";
import { resolve, basename, join } from "node:path";
import { readCodexCloudTasks, submitCodexCloudTask } from "./codex-cloud.mjs";
import { readCodexLocalSessions } from "./codex-local.mjs";

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

async function api(path, body = {}) {
  const result = await fetch(new URL(path, endpoint), {
    method: "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: JSON.stringify(body),
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
  throw new Error("Unsupported task");
}
async function main() {
  console.log(`O-AGENT worker ${id} starting; workspace root: ${root}`);
  let lastCodexSync = 0;
  let lastLocalCodexSync = 0;
  await api("/api/workers/register", { id, name: hostname() });
  while (true) {
    try {
      if (process.env.OAGENT_ENABLE_CODEX_LOCAL_SYNC === "1" && Date.now() - lastLocalCodexSync > 45000) {
        lastLocalCodexSync = Date.now();
        try {
          const sessions = await readCodexLocalSessions();
          await api(`/api/workers/${id}/codex/local/sync`, { sessions });
        } catch {
          console.error("Local Codex CLI sessions unavailable; check Codex app-server support and signed-in Windows user.");
        }
      }
      if (process.env.OAGENT_ENABLE_CODEX_CLOUD_SYNC === "1" && Date.now() - lastCodexSync > 45000) {
        lastCodexSync = Date.now();
        try {
          const tasks = await readCodexCloudTasks();
          await api(`/api/workers/${id}/codex/sync`, { tasks });
        } catch {
          // Never leak CLI output, browser cookies, provider sessions or credentials in worker logs.
          console.error("Codex Cloud sync unavailable; check Codex CLI installation and login.");
        }
      }
      await api(`/api/workers/${id}/heartbeat`);
      const { task } = await api(`/api/workers/${id}/next`);
      if (task) {
        try {
          const result = await execute(task);
          await api(`/api/workers/${id}/tasks/${task.id}/finish`, { ok: true, result });
        } catch (err) {
          await api(`/api/workers/${id}/tasks/${task.id}/finish`, { ok: false, error: String(err.message).slice(0, 1000) });
        }
      }
    } catch (err) {
      console.error("Worker polling error:", err.message);
      try { await api("/api/workers/register", { id, name: hostname() }); } catch { /* retry next cycle */ }
    }
    await sleep(3000);
  }
}
main().catch(err => { console.error(err.message); process.exitCode = 1; });
