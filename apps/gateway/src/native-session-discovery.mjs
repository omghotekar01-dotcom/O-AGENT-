import { realpath } from "node:fs/promises";
import { resolve, sep } from "node:path";

const SESSION_ID = /^[A-Za-z0-9_-]{8,120}$/;
const OS_ENV = new Set(["HOME", "USERPROFILE", "PATH", "APPDATA", "LOCALAPPDATA",
  "HOMEDRIVE", "HOMEPATH", "SYSTEMROOT", "WINDIR", "TEMP", "TMP", "COMSPEC", "XDG_CONFIG_HOME"]);
const safeText = s => typeof s === "string"
  ? s.replace(/[\x00-\x1f\x7f]/g, " ").trim().slice(0, 160) : "";
function safeDate(value) {
  const time = value instanceof Date ? value.getTime()
    : typeof value === "number" ? value : Date.parse(value);
  return Number.isFinite(time) && time > 0 ? new Date(time).toISOString() : null;
}

/** Enumerate SDK-saved sessions scoped to the user's explicitly enrolled directory.
 * Never forward transcripts, tool arguments, external paths, or credentials.
 */
export async function discoverNativeSessions({
  root, env = process.env, importSdk = specifier => import(specifier),
  realpathImpl = realpath,
} = {}) {
  const enrolledRoot = resolve(await realpathImpl(resolve(root || process.cwd()))).toLowerCase();
  const sessions = [], states = {}, seen = new Set();
  async function append(kind, entries, getCwd) {
    for (const item of Array.isArray(entries) ? entries.slice(0, 120) : []) {
      const sessionId = item?.sessionId ?? item?.session_id;
      if (typeof sessionId !== "string" || !SESSION_ID.test(sessionId)) continue;
      const requested = getCwd(item);
      if (typeof requested !== "string" || requested.length < 3 ||
          requested.length > 600 || /[\x00-\x1f]/.test(requested)) continue;
      let cwd;
      try { cwd = resolve(await realpathImpl(resolve(requested))); }
      catch { continue; }
      const normalized = cwd.toLowerCase();
      if (normalized !== enrolledRoot &&
          !normalized.startsWith(enrolledRoot + sep.toLowerCase())) continue;
      const key = kind + "|" + sessionId;
      if (seen.has(key)) continue;
      seen.add(key);
      sessions.push({
        kind, sessionId, cwd,
        title: safeText(item.title || item.summary || "Saved provider session"),
        modifiedAt: safeDate(item.modifiedTime ?? item.lastModified ??
          item.last_modified ?? item.startTime),
      });
      if (sessions.length >= 40) break;
    }
  }
  if (env.OAGENT_ENABLE_CLAUDE_AGENT_SDK === "1") {
    try {
      const sdk = await importSdk("@anthropic-ai/claude-agent-sdk");
      if (typeof sdk.listSessions !== "function") throw Error("Unsupported SDK");
      await append("claude_agent_turn", await sdk.listSessions({limit: 120}), x => x?.cwd);
      states.claude_agent_turn = "metadata_available";
    } catch { states.claude_agent_turn = "sdk_unavailable"; }
  }
  if (env.OAGENT_ENABLE_COPILOT_SDK === "1") {
    let client;
    try {
      const sdk = await importSdk("@github/copilot-sdk");
      if (typeof sdk.CopilotClient !== "function") throw Error("Unsupported SDK");
      const narrowEnv = Object.fromEntries(Object.entries(env).filter(([key, val]) =>
        OS_ENV.has(key.toUpperCase()) && typeof val === "string"));
      client = new sdk.CopilotClient({
        workingDirectory: root, useLoggedInUser: true, env: narrowEnv, logLevel: "error",
      });
      await client.start();
      if (typeof client.listSessions !== "function") throw Error("Unsupported SDK");
      await append("copilot_sdk_turn", await client.listSessions(), x => x?.context?.cwd);
      states.copilot_sdk_turn = "metadata_available";
    } catch { states.copilot_sdk_turn = "sdk_unavailable"; }
    finally { try { await client?.stop?.(); } catch {} }
  }
  return {sessions: sessions.slice(0, 40), states};
}
