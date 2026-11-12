import { randomUUID } from "node:crypto";
import { spawn } from "node:child_process";
import { realpath } from "node:fs/promises";
import { resolve } from "node:path";

const LIMIT_LINE = 1024 * 1024;
const LIMIT_TOTAL = 16 * 1024 * 1024;
const clean = (value, max = 1800) => typeof value === "string" ? value.slice(0, max) : "";
const sleep = ms => new Promise(r => setTimeout(r, ms));

/**
 * One real, user-approved Codex CLI turn, using documented app-server RPC.
 *
 * This is a fresh short-lived app-server owning an explicitly resumed session.
 * It does NOT inject text into another terminal's prompt box, browse a logged-in
 * consumer ChatGPT session, or use a privileged hidden browser.
 *
 * Permission escalation requests are denied by default; for a workspace-write
 * turn a live approval can be explicitly decided from O-AGENT on the phone.
 */
export async function runCodexTurn(task, {
  spawnImpl = spawn,
  realpathImpl = realpath,
  sendUpdate = async () => {},
  askPermission = async () => false,
  env = process.env,
  isWindows = process.platform === "win32",
  timeoutMs = 8 * 60 * 1000,
} = {}) {
  if (task?.kind !== "codex_cli_turn") throw new Error("Expected an approved Codex CLI turn");
  const args = task.parameters ?? {};
  const { sessionId, cwd, prompt, mode } = args;
  if (typeof sessionId !== "string" || !/^[a-zA-Z0-9_-]{8,120}$/.test(sessionId)) throw new Error("Invalid Codex session");
  if (typeof cwd !== "string" || cwd.length < 3 || cwd.length > 600) throw new Error("Invalid Codex workspace");
  if (typeof prompt !== "string" || !prompt.trim() || prompt.length > 4000) throw new Error("Invalid Codex prompt");
  if (!["read_only", "workspace_write"].includes(mode)) throw new Error("Invalid Codex sandbox mode");
  const root = await realpathImpl(cwd);
  if (resolve(root).toLowerCase() !== resolve(cwd).toLowerCase()) {
    throw new Error("Codex workspace path changed since approval; refresh session history");
  }
  // Avoid leaking O-AGENT operator, worker or independent AI API keys to the
  // child process, while retaining official local Codex account auth.
  const childEnv = Object.fromEntries(Object.entries(env).filter(([key]) =>
    !/^(OAGENT_(API|WORKER)_TOKEN|OAGENT_GITHUB_TOKEN|OPENAI_API_KEY|ANTHROPIC_API_KEY|OAGENT_CODEX_TASK_PROMPT)$/i.test(key)
  ));
  const bin = isWindows ? "powershell.exe" : "codex";
  const argv = isWindows
    ? ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", "& codex app-server"]
    : ["app-server"];
  return new Promise((resolvePromise, rejectPromise) => {
    let child;
    try {
      child = spawnImpl(bin, argv, { stdio: ["pipe", "pipe", "pipe"], cwd: root, env: childEnv, windowsHide: true });
    } catch { rejectPromise(new Error("Codex CLI cannot start its app-server")); return; }
    let finished = false, stage = 0, total = 0, textBuffer = "", turnId = null, lastText = "";
    let deltaBuffer = "", flushTimer = null;
    let deliveries = Promise.resolve(), deliveryError = null;
    const timeout = setTimeout(() => finish(new Error("Codex turn timed out")), timeoutMs);
    function enqueue(type, text = "") {
      const value = clean(text, 2500);
      deliveries = deliveries.then(() => sendUpdate({ type, text: value })).catch(error => {
        deliveryError = error;
        finish(new Error("Cannot deliver Codex activity to authenticated O-AGENT backend"));
      });
    }
    function flush() {
      if (flushTimer) clearTimeout(flushTimer);
      flushTimer = null;
      if (deltaBuffer) { const value = deltaBuffer; deltaBuffer = ""; enqueue("agent_delta", value); }
    }
    function appendDelta(value) {
      if (typeof value !== "string") return;
      lastText = (lastText + value).slice(-8000);
      deltaBuffer += value;
      if (deltaBuffer.length >= 1200) flush();
      else if (!flushTimer) flushTimer = setTimeout(flush, 400);
    }
    function write(value) {
      if (!finished) child.stdin.write(JSON.stringify(value) + "\n");
    }
    function request(id, method, params) { write({ id, method, params }); }
    function finish(error, result) {
      if (finished) return;
      finished = true;
      flush();
      clearTimeout(timeout);
      try { child.stdin.end(); } catch {}
      try { child.kill(); } catch {}
      deliveries.then(() => {
        if (error || deliveryError) rejectPromise(error || deliveryError);
        else resolvePromise(result);
      }, rejectPromise);
    }
    function failProvider(message) { finish(new Error(clean(message, 450) || "Codex provider error")); }
    async function permission(msg) {
      const method = msg.method || "";
      const details = msg.params ?? {};
      const isCommand = method === "item/commandExecution/requestApproval";
      const isFile = method === "item/fileChange/requestApproval";
      const isPermission = method === "item/permissions/requestApproval";
      // Do not turn a vague request into a broad privilege grant. Additional
      // filesystem/network permissions require a separate, richer UI and are
      // denied rather than showing an incomplete approval summary.
      const networkAccess = details.networkApprovalContext != null;
      const additionalAccess = details.additionalPermissions != null;
      const grantRoot = typeof details.grantRoot === "string" ? resolve(details.grantRoot) : "";
      const outsideRoot = grantRoot && grantRoot.toLowerCase() !== resolve(root).toLowerCase();
      const hasKnownCommand = typeof details.command === "string" && details.command.trim().length > 0;
      if ((!isCommand && !isFile) || mode === "read_only" || isPermission ||
          networkAccess || additionalAccess || outsideRoot || (isCommand && !hasKnownCommand)) {
        write({ id: msg.id, result: { decision: "decline" } });
        enqueue("status", "Provider requested unsupported or elevated access; denied safely");
        return;
      }
      const requestId = randomUUID();
      const detailParts = [
        isCommand ? "Command execution request" : isFile ? "File modification request" : "Permission escalation request",
        clean(details.reason, 300),
        clean(details.command, 600),
        clean(details.cwd, 300),
        clean(details.grantRoot, 300),
        isPermission ? "Requested extra filesystem or network permissions" : "",
      ].filter(Boolean);
      enqueue("status", "Codex is waiting for a device approval");
      let approved = false;
      try {
        approved = await askPermission({
          id: requestId, kind: isCommand ? "command" : isFile ? "file_change" : "permissions",
          description: detailParts.join("\n").slice(0, 1200),
        });
      } catch { approved = false; }
      write({ id: msg.id, result: { decision: approved ? "accept" : "decline" } });
      enqueue("status", approved ? "Permission explicitly approved" : "Permission denied or expired");
    }
    function handle(msg) {
      if (!msg || typeof msg !== "object") return;
      if (Object.hasOwn(msg, "id") && typeof msg.method === "string") {
        void permission(msg);
        return;
      }
      if (msg.id === 1 && stage === 0) {
        if (msg.error) return failProvider("Codex app-server initialization rejected");
        stage = 1;
        write({ method: "initialized", params: {} });
        request(2, "thread/resume", { threadId: sessionId });
        return;
      }
      if (msg.id === 2 && stage === 1) {
        if (msg.error) return failProvider("Could not resume this Codex session. It may be owned by another active process; close that turn and retry.");
        stage = 2;
        enqueue("session_resumed", "Resumed real Codex session " + sessionId.slice(0, 8));
        const sandboxPolicy = mode === "workspace_write"
          ? { type: "workspaceWrite", writableRoots: [root], networkAccess: false,
              readOnlyAccess: { type: "restricted", includePlatformDefaults: true, readableRoots: [root] } }
          : { type: "readOnly",
              access: { type: "restricted", includePlatformDefaults: true, readableRoots: [root] } };
        request(3, "turn/start", {
          threadId: sessionId,
          input: [{ type: "text", text: prompt }],
          cwd: root, approvalPolicy: "on-request", sandboxPolicy,
        });
        return;
      }
      if (msg.id === 3 && stage === 2) {
        if (msg.error) return failProvider("Codex rejected turn/start: " + clean(msg.error.message, 220));
        turnId = msg.result?.turn?.id ?? null;
        if (!turnId) return failProvider("Codex returned no running turn ID");
        stage = 3;
        enqueue("turn_started", "Codex turn " + turnId);
        return;
      }
      if (!msg.method || stage < 2) return;
      const params = msg.params ?? {};
      if (params.threadId && params.threadId !== sessionId) return;
      if (msg.method === "item/agentMessage/delta") {
        appendDelta(params.delta);
      } else if (msg.method === "item/started" || msg.method === "item/completed") {
        const item = params.item ?? {};
        if (item.type === "agentMessage") {
          if (msg.method === "item/completed" && !lastText && item.text) appendDelta(item.text);
        } else {
          const kind = clean(item.type, 60) || "tool";
          const description = item.type === "commandExecution" ? clean(item.command, 700)
            : item.type === "fileChange" ? "File changes in the approved workspace" : kind;
          enqueue(msg.method === "item/started" ? "tool_started" : "tool_finished", description || kind);
        }
      } else if (msg.method === "error") {
        enqueue("error", clean(params.error?.message, 500) || "Codex reported a model/tool error");
      } else if (msg.method === "turn/completed") {
        if (turnId && params.turn?.id && params.turn.id !== turnId) return;
        flush();
        const providerStatus = params.turn?.status || "unknown";
        enqueue("turn_completed", providerStatus);
        finish(null, {
          provider: "codex_cli", threadId: sessionId, turnId,
          providerStatus, output: lastText, completedAt: new Date().toISOString(),
        });
      }
    }
    child.on("error", () => finish(new Error("Failed to start Codex app-server")));
    child.on("exit", () => { if (!finished) finish(new Error("Codex app-server exited before turn completion")); });
    child.stdout.on("data", chunk => {
      if (finished) return;
      total += chunk.length;
      if (total > LIMIT_TOTAL) return finish(new Error("Codex output volume exceeded safety limit"));
      textBuffer += chunk.toString("utf8");
      let end;
      while (!finished && (end = textBuffer.indexOf("\n")) >= 0) {
        const line = textBuffer.slice(0, end).trim();
        textBuffer = textBuffer.slice(end + 1);
        if (!line) continue;
        if (line.length > LIMIT_LINE) return finish(new Error("Oversized Codex protocol message"));
        try { handle(JSON.parse(line)); } catch { /* ignore malformed provider output */ }
      }
      if (textBuffer.length > LIMIT_LINE) finish(new Error("Codex protocol line exceeded limit"));
    });
    child.stderr.on("data", () => {}); // Don't leak private CLI context to worker logs.
    request(1, "initialize", { clientInfo: { name: "o_agent", title: "O-AGENT supervised session", version: "0.2.0" } });
  });
}
