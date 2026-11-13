import { spawn } from "node:child_process";
import { basename, normalize } from "node:path";
import { codexChildEnv } from "./codex-env.mjs";

const MAX_SESSIONS = 80;
const MAX_LINE = 2 * 1024 * 1024;

/**
 * Discovers genuine local Codex CLI/IDE sessions via the official
 * codex app-server JSON-RPC protocol. Never reads ~/.codex/auth.json,
 * browser cookies, tokens, raw rollout files or executes a Codex turn.
 */
export async function readCodexLocalSessions({
  spawnImpl = spawn,
  isWindows = process.platform === "win32",
  env = process.env,
  timeoutMs = 25000,
} = {}) {
  const executable = isWindows ? "powershell.exe" : "codex";
  // PowerShell is only needed to resolve npm's codex.cmd shim. No user
  // data or external arguments are included in the shell script.
  const args = isWindows
    ? ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", "& codex app-server"]
    : ["app-server"];
  const childEnv = codexChildEnv(env);
  return new Promise((resolve, reject) => {
    let child;
    try {
      child = spawnImpl(executable, args, {
        stdio: ["pipe", "pipe", "pipe"],
        windowsHide: true,
        env: childEnv,
      });
    } catch { reject(new Error("Cannot launch the authenticated Codex app-server")); return; }
    let done = false;
    let stage = 0;
    let buffer = "";
    let total = 0;
    const timer = setTimeout(() => finish(new Error("Codex local session discovery timed out")), timeoutMs);
    function finish(error, value) {
      if (done) return;
      done = true;
      clearTimeout(timer);
      // EOF closes the app-server stdio lifecycle. Kill if still present to
      // avoid accumulating background Codex processes on every poll.
      try { child.stdin.end(); } catch {}
      try { child.kill(); } catch {}
      if (error) reject(error);
      else resolve(value);
    }
    function send(message) {
      if (!done) child.stdin.write(JSON.stringify(message) + "\n");
    }
    function handle(response) {
      if (typeof response !== "object" || response === null) return;
      if (response.id === 1 && stage === 0) {
        if (response.error) return finish(new Error("Codex app-server initialization failed"));
        stage = 1;
        send({ method: "initialized", params: {} });
        send({
          id: 2, method: "thread/list",
          params: { limit: 100, sortKey: "updated_at", sortDirection: "desc", currentAccountOnly: true },
        });
      } else if (response.id === 2 && stage === 1) {
        if (response.error) return finish(new Error("Codex session listing was rejected by the CLI"));
        try { finish(null, normalizeCodexLocalSessions(response.result)); }
        catch { finish(new Error("Codex returned an invalid session list")); }
      }
    }
    child.on("error", () => finish(new Error("Codex app-server could not be started")));
    child.on("exit", () => { if (!done) finish(new Error("Codex app-server exited before listing sessions")); });
    child.stdout.on("data", chunk => {
      if (done) return;
      total += chunk.length;
      if (total > MAX_LINE * 2) return finish(new Error("Codex session response too large"));
      buffer += chunk.toString("utf8");
      let index;
      while (!done && (index = buffer.indexOf("\n")) >= 0) {
        const line = buffer.slice(0, index).trim();
        buffer = buffer.slice(index + 1);
        if (!line || line.length > MAX_LINE) continue;
        let event;
        try { event = JSON.parse(line); } catch { continue; }
        handle(event);
      }
      if (buffer.length > MAX_LINE) finish(new Error("Codex session line exceeds limit"));
    });
    // Do not echo stderr: the CLI may write provider/account details to it.
    child.stderr.on("data", () => {});
    send({
      id: 1, method: "initialize",
      params: {
        clientInfo: { name: "o_agent", title: "O-AGENT read-only project discovery", version: "0.1.0" },
      },
    });
  });
}

export function normalizeCodexLocalSessions(data) {
  if (!data || !Array.isArray(data.data)) throw new Error("Expected Codex app-server thread/list data");
  const seen = new Set();
  const output = [];
  for (const t of data.data) {
    if (!t || typeof t !== "object") continue;
    if (typeof t.id !== "string" || !/^[A-Za-z0-9_-]{8,120}$/.test(t.id) || seen.has(t.id)) continue;
    if (typeof t.cwd !== "string" || t.cwd.length < 2 || t.cwd.length > 600) continue;
    const cwd = normalize(t.cwd);
    if (!cwd || cwd === "." || cwd === ".." || cwd.includes("\u0000")) continue;
    const state = t.status?.type;
    const allowedStates = new Set(["notLoaded", "idle", "active", "systemError"]);
    const updatedSeconds = Number(t.updatedAt ?? t.recencyAt ?? 0);
    const createdSeconds = Number(t.createdAt ?? 0);
    const dateValue = n => Number.isFinite(n) && n > 0 && n < 4102444800 ? new Date(n * 1000).toISOString() : null;
    const flags = Array.isArray(t.status?.activeFlags)
      ? t.status.activeFlags.filter(x => typeof x === "string").slice(0, 4) : [];
    // "notLoaded" only means that THIS app-server does not own the thread.
    // It does NOT prove the original CLI or IDE thread is inactive.
    output.push({
      id: t.id,
      title: typeof t.preview === "string" && t.preview.trim()
        ? t.preview.replace(/[\r\n\t]+/g, " ").slice(0, 180)
        : "Codex session " + t.id.slice(0, 8),
      cwd: cwd.slice(0, 600),
      workspaceName: basename(cwd) || cwd.slice(-80),
      updatedAt: dateValue(updatedSeconds),
      createdAt: dateValue(createdSeconds),
      state: allowedStates.has(state) ? state : "unknown",
      activeFlags: flags,
      modelProvider: typeof t.modelProvider === "string" ? t.modelProvider.slice(0, 80) : null,
      source: "codex_cli",
    });
    seen.add(t.id);
    if (output.length >= MAX_SESSIONS) break;
  }
  return output;
}
