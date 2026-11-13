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
  async createAgent(key, {
    prompt, repoUrl, startingRef, mode = "plan",
    autoCreatePR = false, agentId,
  } = {}) {
    // A new agent is a potentially billable run with repository write access.
    // Never send an unchecked repo URL or allow direct pushes to its branch.
    const p = nonempty(prompt, "agent prompt", 4000);
    const target = nonempty(repoUrl, "repository URL", 350);
    let parsed;
    try { parsed = new URL(target); } catch { /* invalid URL */ }
    if (!parsed || parsed.protocol !== "https:" ||
        !parsed.hostname.includes(".") || parsed.username ||
        parsed.password || parsed.port || parsed.search || parsed.hash ||
        !/^\/[^/]+\/[^/]+(?:\/[^/]+)*\/?$/.test(parsed.pathname)) {
      throw new DomainError(400, "Enter a valid HTTPS repository URL");
    }
    if (startingRef != null && (typeof startingRef !== "string" ||
        !/^[A-Za-z0-9._/-]{1,120}$/.test(startingRef) ||
        startingRef.includes(".."))) {
      throw new DomainError(400, "Invalid starting branch");
    }
    if (mode !== "plan" && mode !== "agent")
      throw new DomainError(400, "Invalid agent mode");
    if (typeof autoCreatePR !== "boolean")
      throw new DomainError(400, "Invalid PR setting");
    if (typeof agentId !== "string" ||
        !/^bc-[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(agentId))
      throw new DomainError(400, "Invalid idempotent agent identifier");
    const raw = await this.request(key, "/v1/agents", {
      method: "POST", body: {
        agentId, prompt: { text: p },
        repos: [{ url: parsed.toString(),
          ...(startingRef ? { startingRef } : {}) }],
        workOnCurrentBranch: false,
        autoCreatePR, mode,
      },
    });
    return { agent: oneAgent(raw.agent), run: oneRun(raw.run) };
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
  // Run-scoped Cursor SSE. This is verified provider output, NOT a desktop
  // screenshot or hidden chain-of-thought stream. Thinking and raw tool
  // results are intentionally not forwarded to reduce secret leakage.
  async *streamRun(key, agentId, runId, { lastEventId, signal } = {}) {
    const a = identifier(agentId, "agent ID");
    const r = identifier(runId, "run ID");
    if (lastEventId != null &&
        (typeof lastEventId !== "string" || !/^[A-Za-z0-9_-]{1,160}$/.test(lastEventId)))
      throw new DomainError(400, "Invalid Cursor event cursor");
    const url = ORIGIN + "/v1/agents/" + a + "/runs/" + r + "/stream";
    let response;
    try {
      response = await this.fetchImpl(url, {
        method: "GET", redirect: "error", signal,
        headers: {
          Authorization: "Bearer " + nonempty(key, "Cursor key", 1024),
          Accept: "text/event-stream",
          ...(lastEventId ? { "Last-Event-ID": lastEventId } : {}),
        },
      });
    } catch {
      if (signal?.aborted) return;
      throw new DomainError(503, "Cursor live stream unavailable");
    }
    if (!response.ok) {
      if (response.status === 410) throw new DomainError(410,
        "Cursor stream expired; load the final run result instead");
      throw new DomainError([401,403,404,429].includes(response.status)
        ? response.status : 502, "Cursor live stream rejected");
    }
    if (!response.body || typeof response.body[Symbol.asyncIterator] !== "function")
      throw new DomainError(502, "Cursor did not return a readable event stream");
    const decoder = new TextDecoder();
    let buffered = "", event = "message", id = null, data = [];
    const normalize = () => {
      let payload;
      try { payload = JSON.parse(data.join("\n")); }
      catch { return null; }
      if (!payload || typeof payload !== "object") return null;
      if (event === "assistant") return {
        event, id, data: { text: text(payload.text, 3500) },
      };
      if (event === "status") return {
        event, id, data: { status: text(payload.status, 50),
          runId: text(payload.runId, 120) },
      };
      if (event === "tool_call") return {
        event, id, data: { name: text(payload.name, 120),
          status: text(payload.status, 50) },
      };
      if (event === "result") return {
        event, id, data: { text: text(payload.text, 15000),
          status: text(payload.status, 50) },
      };
      if (event === "done") return { event, id, data: {} };
      return null;
    };
    for await (const chunk of response.body) {
      if (signal?.aborted) return;
      buffered += decoder.decode(chunk, { stream: true });
      if (buffered.length > 65536) throw new DomainError(502,
        "Cursor stream frame exceeded safe length");
      let i;
      while ((i = buffered.indexOf("\n")) >= 0) {
        const line = buffered.slice(0, i).replace(/\r$/, "");
        buffered = buffered.slice(i + 1);
        if (!line) {
          const result = normalize();
          if (result) yield result;
          event = "message"; id = null; data = [];
        } else if (line.startsWith("event:")) event = line.slice(6).trim();
        else if (line.startsWith("id:")) id = line.slice(3).trim().slice(0, 160);
        else if (line.startsWith("data:")) {
          data.push(line.slice(5).trimStart());
          if (data.join("").length > 18000)
            throw new DomainError(502, "Cursor event exceeded safe length");
        }
      }
    }
    const last = normalize();
    if (last) yield last;
  }

  async cancelRun(key, agentId, runId) {
    const a = identifier(agentId, "agent ID"), r = identifier(runId, "run ID");
    const raw = await this.request(key, "/v1/agents/" + a + "/runs/" + r + "/cancel",
      { method: "POST" });
    return { id: text(raw.id, 120), cancelled: true };
  }
}
