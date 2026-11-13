import { randomUUID } from "node:crypto";
import { realpath } from "node:fs/promises";
import { resolve, sep } from "node:path";

const RUN_TYPES = new Map([
  ["claude_agent_turn", { env: "OAGENT_ENABLE_CLAUDE_AGENT_SDK", pkg: "@anthropic-ai/claude-agent-sdk" }],
  ["copilot_sdk_turn", { env: "OAGENT_ENABLE_COPILOT_SDK", pkg: "@github/copilot-sdk" }],
]);
const READ_TOOLS = new Set(["Read", "Glob", "Grep", "read_file", "glob", "grep", "view"]);
const WRITE_TOOLS = new Set(["Edit", "Write", "MultiEdit", "NotebookEdit", "Bash",
  "edit", "write_file", "shell", "bash", "create_file"]);
const MAX_PROMPT = 4000;
const summarize = (s, n = 1200) => typeof s === "string" ? s.slice(0, n) : "";
const safeIdentifier = s => typeof s === "string" && /^[a-zA-Z0-9_-]{8,120}$/.test(s);
function safeEnv(env) {
  return Object.fromEntries(Object.entries(env).filter(([key, value]) =>
    typeof value === "string" && !/TOKEN|PASSWORD|SECRET|API_KEY|PRIVATE_KEY|OAGENT_.*KEY/i.test(key)));
}
function permittedPath(path, root) {
  const p = resolve(path).toLowerCase(), r = resolve(root).toLowerCase();
  return p === r || p.startsWith(r + sep.toLowerCase());
}
function briefAction(tool, details) {
  const candidate = details?.file_path ?? details?.path ?? details?.fileName ??
    details?.fullCommandText ?? details?.command ?? details?.description;
  return summarize("Tool " + tool + ": " + (typeof candidate === "string"
    ? candidate : "access request with no safe details"), 1000);
}
function safeDelta(text) {
  return typeof text === "string" ? text.slice(0, 1800) : "";
}
function parseClaudeMessage(message, sink) {
  if (!message || typeof message !== "object") return;
  if (message.type === "system" && message.subtype === "init" && safeIdentifier(message.session_id))
    sink.sessionId = message.session_id;
  if (message.type === "stream_event") {
    const event = message.event;
    if (event?.type === "content_block_delta" && event.delta?.type === "text_delta")
      sink.onDelta(safeDelta(event.delta.text));
  }
  if (message.type === "assistant" && Array.isArray(message.message?.content)) {
    for (const block of message.message.content) {
      if (block.type === "tool_use")
        sink.onStatus("Tool requested: " + summarize(block.name, 90));
      // When streaming partial events are missing, forward the final message
      // as a bounded result, not raw thinking/tool input or environment values.
    }
  }
  if (message.type === "result") {
    sink.resultText = summarize(message.result, 8000);
    sink.cost = Number.isFinite(message.total_cost_usd) ? message.total_cost_usd : null;
  }
}

/**
 * Official SDK-owned supervised turn. This never injects into another user's
 * already open ChatGPT/Copilot/Claude website, terminal UI, or IDE tab.
 * Optional SDK imports require deliberate installation on the enrolled worker.
 */
export async function runProviderTurn(task, {
  importSdk = specifier => import(specifier),
  realpathImpl = realpath,
  sendUpdate = async () => {},
  askPermission = async () => false,
  env = process.env,
  timeoutMs = 8 * 60 * 1000,
} = {}) {
  const type = RUN_TYPES.get(task?.kind);
  if (!type) throw Error("Unsupported provider bridge type");
  if (env[type.env] !== "1") throw Error("This provider bridge is not enabled on this worker");
  const { cwd, prompt, mode = "read_only", sessionId = null } = task.parameters ?? {};
  if (typeof prompt !== "string" || !prompt.trim() || prompt.length > MAX_PROMPT)
    throw Error("Invalid provider prompt");
  if (typeof cwd !== "string" || cwd.length < 3 || cwd.length > 600)
    throw Error("Invalid workspace folder");
  if (!["read_only", "workspace_write"].includes(mode))
    throw Error("Unsupported provider execution mode");
  if (sessionId !== null && !safeIdentifier(sessionId))
    throw Error("Invalid provider-owned session ID");

  const root = await realpathImpl(env.OAGENT_WORKSPACE_ROOT || process.cwd());
  const actual = await realpathImpl(cwd);
  if (!permittedPath(actual, root) || resolve(actual).toLowerCase() !== resolve(cwd).toLowerCase())
    throw Error("Workspace must be an existing folder inside enrolled worker root");
  const sdk = await importSdk(type.pkg).catch(() => {
    throw Error(type.pkg + " unavailable: install the official SDK on the enrolled machine");
  });
  const abort = new AbortController();
  const timer = setTimeout(() => abort.abort(), timeoutMs);
  let session = null, sessionHandle = null, client = null, completed = false, messages = 0, finalText = "", cost = null;
  let updates = Promise.resolve(), deliveryFailure = null;
  const enqueue = (eventType, text = "") => {
    if (deliveryFailure) return;
    if (messages++ > 700) return;
    updates = updates.then(() => sendUpdate({
      type: eventType, text: summarize(text, 2400),
    })).catch(err => {
      deliveryFailure = err || Error("Cannot deliver agent events to the server");
      abort.abort();
    });
  };
  const ask = async (tool, input, kind = "permissions") => {
    if (abort.signal.aborted || mode !== "workspace_write") return false;
    if (!WRITE_TOOLS.has(tool) && !["shell", "write"].includes(tool))
      return false; // No network, MCP, browser, external folders, unknown tools.
    const fields = input && typeof input === "object" ? input : {};
    for (const key of ["file_path", "path", "fileName", "cwd", "workingDirectory"]) {
      if (typeof fields[key] === "string" &&
          !permittedPath(resolve(actual, fields[key]), actual)) return false;
    }
    // Each request gets its own random ID, fresh expiry and exact decision.
    const decision = await askPermission({
      id: randomUUID(), kind,
      description: briefAction(tool, fields),
    });
    return decision === true && !abort.signal.aborted;
  };
  try {
    if (task.kind === "claude_agent_turn") {
      if (typeof sdk.query !== "function") throw Error("Claude Agent SDK has no query() API");
      const state = {
        sessionId, resultText: "", cost: null,
        onDelta: value => { finalText = (finalText + value).slice(-8000); enqueue("agent_delta", value); },
        onStatus: value => enqueue("status", value),
      };
      const iterable = sdk.query({
        prompt,
        options: {
          cwd: actual, ...(sessionId ? { resume: sessionId } : {}),
          permissionMode: "default",
          // Restrict auto-approved tools to read-only operations.
          allowedTools: [...READ_TOOLS].filter(n => /^[A-Z]/.test(n)),
          disallowedTools: mode === "read_only"
            ? ["Bash", "Edit", "Write", "MultiEdit", "NotebookEdit", "WebFetch", "WebSearch"]
            : ["WebFetch", "WebSearch"],
          canUseTool: async (toolName, input) => {
            if (READ_TOOLS.has(toolName)) {
              // SDK read operations remain within OS permissions. Tool-supplied
              // path is checked when present, no mass permission granted.
              const file = input?.file_path ?? input?.path;
              if (typeof file === "string" &&
                  !permittedPath(resolve(actual, file), actual))
                return { behavior: "deny", message: "Outside enrolled workspace" };
              return { behavior: "allow", updatedInput: input };
            }
            const allowed = await ask(toolName, input, "permissions");
            return allowed
              ? { behavior: "allow", updatedInput: input }
              : { behavior: "deny", message: "O-AGENT mobile approval denied or expired" };
          },
          includePartialMessages: true, maxTurns: 20,
          abortController: abort,
          env: safeEnv(env),
        },
      });
      for await (const item of iterable) {
        if (abort.signal.aborted) throw Error("Claude agent turn timed out or stopped");
        parseClaudeMessage(item, state);
      }
      finalText = state.resultText || finalText;
      session = state.sessionId;
      cost = state.cost;
      completed = true;
    } else {
      if (typeof sdk.CopilotClient !== "function")
        throw Error("GitHub Copilot SDK has no CopilotClient API");
      client = new sdk.CopilotClient({
        workingDirectory: actual, useLoggedInUser: true,
        env: safeEnv(env), logLevel: "error",
      });
      await client.start();
      const options = {
        workingDirectory: actual, streaming: true,
        // managed policies are still enforced by Copilot's own runtime.
        hooks: {
          onPreToolUse: async input => ({
            permissionDecision: READ_TOOLS.has(input?.toolName)
              ? "allow" : mode === "workspace_write" ? "ask" : "deny",
          }),
        },
        onPermissionRequest: async request => {
          if (request?.kind === "read") {
            const path = request.path;
            if (typeof path !== "string" ||
                permittedPath(resolve(actual, path), actual))
              return { kind: "approve-once" };
            return { kind: "reject", feedback: "Outside enrolled workspace" };
          }
          const name = request?.kind === "shell" ? "shell"
            : request?.kind === "write" ? "write" : "unknown";
          const yes = await ask(name, request, "permissions");
          return yes ? { kind: "approve-once" }
            : { kind: "reject", feedback: "Owner denied or timed out the request" };
        },
      };
      sessionHandle = sessionId
        ? await client.resumeSession(sessionId, options)
        : await client.createSession(options);
      const onDelta = event => {
        const chunk = safeDelta(event?.data?.deltaContent);
        if (chunk) { finalText = (finalText + chunk).slice(-8000); enqueue("agent_delta", chunk); }
      };
      sessionHandle.on("assistant.message_delta", onDelta);
      sessionHandle.on("tool.execution_start", event =>
        enqueue("status", "Tool started: " + summarize(event?.data?.toolName, 80)));
      const result = await sessionHandle.sendAndWait({ prompt }, timeoutMs);
      finalText = summarize(result?.data?.content, 8000) || finalText;
      session = sessionHandle.sessionId ?? sessionHandle.id ?? sessionId;
      completed = true;
    }
    enqueue("turn_completed", "Provider completed the supervised turn");
    await updates;
    if (deliveryFailure) throw Error("Agent event delivery failed");
    return { providerStatus: completed ? "completed" : "failed",
      sessionId: typeof session === "string" ? session : null,
      response: summarize(finalText, 8000), costUsd: cost };
  } finally {
    clearTimeout(timer);
    abort.abort();
    // Copilot sessions must be shut down in a finally block even when a
    // permission request times out. No worker may stay attached silently.
    if (sessionHandle) {
      try { await sessionHandle.disconnect?.(); } catch {}
    }
    try { await client?.stop?.(); } catch {}
  }
}
