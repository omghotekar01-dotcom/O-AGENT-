import { DomainError } from "./core.mjs";

// Official Cursor Cloud Agents v1 REST adapter. Never accepts an arbitrary URL
// from a caller. This only drives agents already available to the user's API key.
const ORIGIN = "https://api.cursor.com";
const AGENT_ID = /^[A-Za-z0-9_-]{8,120}$/;
const LIMIT = 30;

function nonempty(value, label, max) {
  if (typeof value !== "string" || !value.trim() || value.length > max)
    throw new DomainError(400, "Invalid " + label);
  return value.trim();
}
function identifier(value, label) {
  const v = nonempty(value, label, 120);
  if (!AGENT_ID.test(v)) throw new DomainError(400, "Invalid " + label);
  return v;
}
function text(value, max = 280) {
  return typeof value === "string" ? value.slice(0, max) : "";
}
function timestamp(value) {
  return typeof value === "string" && !Number.isNaN(Date.parse(value))
    ? value.slice(0, 50) : null;
}
function safeUrl(url) {
  if (typeof url !== "string" || url.length > 500) return null;
  try {
    const parsed = new URL(url);
    return parsed.protocol === "https:" &&
      (parsed.hostname === "cursor.com" || parsed.hostname === "www.cursor.com") &&
      /^\/agents\/[A-Za-z0-9_-]+\/?$/.test(parsed.pathname)
      ? parsed.toString() : null;
  } catch { return null; }
}
function oneAgent(item) {
  return {
    id: text(item?.id, 120), name: text(item?.name, 200) || "Cloud agent",
    status: text(item?.status, 35), url: safeUrl(item?.url),
    latestRunId: text(item?.latestRunId, 120) || null,
    createdAt: timestamp(item?.createdAt), updatedAt: timestamp(item?.updatedAt),
    environment: text(item?.env?.type, 50) || null,
  };
}
function oneRun(item) {
  return {
    id: text(item?.id, 120), agentId: text(item?.agentId, 120),
    status: text(item?.status, 48),
    createdAt: timestamp(item?.createdAt), updatedAt: timestamp(item?.updatedAt),
    durationMs: Number.isSafeInteger(item?.durationMs) ? item.durationMs : null,
    result: text(item?.result, 16000) || null,
    branches: Array.isArray(item?.git?.branches)
      ? item.git.branches.slice(0, 12).map(b => ({
        repo: text(b?.repoUrl, 250), branch: text(b?.branch, 160),
        // Do not trust arbitrary provider-supplied destination URLs.
        prUrl: typeof b?.prUrl === "string" && /^https:\/\/github\.com\/[\w.-]+\/[\w.-]+\/pull\/\d+(?:\/)?$/.test(b.prUrl)
          ? b.prUrl : null,
      })) : [],
  };
}
export class CursorCloudClient {
  constructor({ fetchImpl = fetch, timeoutMs = 16000 } = {}) {
    this.fetchImpl = fetchImpl;
    this.timeoutMs = timeoutMs;
  }
  async request(key, path, { method = "GET", body } = {}) {
    nonempty(key, "Cursor API key", 1024);
    if (!path.startsWith("/v1/") || path.includes("..") ||
        !/^[A-Za-z0-9/?=&_-]+$/.test(path)) {
      throw new DomainError(400, "Invalid Cursor API path");
    }
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const response = await this.fetchImpl(ORIGIN + path, {
        method,
        headers: {
          "Authorization": "Bearer " + key,
          "Accept": "application/json",
          ...(body ? { "Content-Type": "application/json" } : {}),
        },
        ...(body ? { body: JSON.stringify(body) } : {}),
        signal: controller.signal,
        redirect: "error",
      });
      const raw = await response.text();
      if (raw.length > 300000) throw new DomainError(502, "Cursor response exceeded safe size");
      let data;
      try { data = raw ? JSON.parse(raw) : {}; }
      catch { throw new DomainError(502, "Invalid response from Cursor"); }
      if (!response.ok) {
        const upstream = data?.error?.code;
        // Only expose a narrowly allowlisted Cursor error code. Never echo
        // raw upstream messages because they may embed provider secrets.
        const allowed = new Set([
          "invalid_api_key","unauthorized","permission_required",
          "feature_unavailable","plan_required","agent_busy",
          "run_not_cancellable","validation_error","rate_limit_exceeded",
          "agent_not_found","run_not_found","key_not_supported",
        ]);
        const reason = typeof upstream === "string" && allowed.has(upstream)
          ? upstream.replaceAll("_", " ") : "provider rejected request";
        const status = [400,401,403,404,409,429].includes(response.status)
          ? response.status : 502;
        throw new DomainError(status, "Cursor Cloud: " + reason);
      }
      if (!data || typeof data !== "object" || Array.isArray(data))
        throw new DomainError(502, "Unexpected Cursor response");
      return data;
    } catch (error) {
      if (error instanceof DomainError) throw error;
      throw new DomainError(503,
        "Cursor Cloud network unavailable. Check the run before retrying any write.");
    } finally { clearTimeout(timer); }
  }
  async verify(key) {
    // /v1/me returns verified key identity without triggering a paid run.
    const me = await this.request(key, "/v1/me");
    return {
      keyName: text(me.apiKeyName, 120) || "Cursor API key",
      // Users may connect a team service account, which has no userEmail.
      identity: text(me.userEmail, 200) || "Service account",
    };
  }
  async listAgents(key) {
    const raw = await this.request(key, "/v1/agents?limit=" + LIMIT);
    if (!Array.isArray(raw.items)) throw new DomainError(502, "Invalid Cursor agent list");
    return { agents: raw.items.slice(0, LIMIT).map(oneAgent),
      nextCursorAvailable: !!raw.nextCursor };
  }
  async getAgent(key, agentId) {
    const raw = await this.request(key, "/v1/agents/" + identifier(agentId, "agent ID"));
    const agent = oneAgent(raw);
    return { ...agent, repos: Array.isArray(raw.repos) ? raw.repos.slice(0, 12)
      .map(r => ({ url: text(r?.url, 300), ref: text(r?.startingRef, 150) })) : [] };
  }
  async listRuns(key, agentId) {
    const raw = await this.request(key, "/v1/agents/" +
      identifier(agentId, "agent ID") + "/runs?limit=20");
    if (!Array.isArray(raw.items)) throw new DomainError(502, "Invalid Cursor run list");
    return { runs: raw.items.slice(0, 20).map(oneRun),
      nextCursorAvailable: !!raw.nextCursor };
  }
  async getRun(key, agentId, runId) {
    const raw = await this.request(key, "/v1/agents/" +
      identifier(agentId, "agent ID") + "/runs/" + identifier(runId, "run ID"));
    return oneRun(raw);
  }
  async followUp(key, agentId, { prompt, delivery } = {}) {
    const a = identifier(agentId, "agent ID");
    const p = nonempty(prompt, "agent prompt", 4000);
    if (delivery != null && delivery !== "steer")
      throw new DomainError(400, "Invalid delivery mode");
    const raw = await this.request(key, "/v1/agents/" + a + "/runs", {
      method: "POST", body: { prompt: { text: p }, ...(delivery ? { delivery } : {}) },
    });
    return delivery ? {
      delivery: text(raw.delivery, 40), runId: text(raw.runId, 120) || null,
    } : { run: oneRun(raw.run) };
  }
  async cancelRun(key, agentId, runId) {
    const a = identifier(agentId, "agent ID"), r = identifier(runId, "run ID");
    const raw = await this.request(key, "/v1/agents/" + a + "/runs/" + r + "/cancel",
      { method: "POST" });
    return { id: text(raw.id, 120), cancelled: true };
  }
}
