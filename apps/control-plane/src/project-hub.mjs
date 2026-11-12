import { randomUUID } from "node:crypto";
import { DomainError } from "./core.mjs";

const REPO_NAME = /^[A-Za-z0-9_.-]{1,100}\/[A-Za-z0-9_.-]{1,100}$/;
const MAX_REPOS = 8;
function repoSpec(env) {
  return [...new Set((env.OAGENT_GITHUB_REPOS || "").split(",").map(x => x.trim()).filter(Boolean))].slice(0, MAX_REPOS).filter(x => REPO_NAME.test(x));
}
function safeTitle(value, key, max = 160) {
  if (typeof value !== "string" || !value.trim() || value.length > max) throw new DomainError(400, "Invalid " + key);
  return value.trim();
}
function shorten(text, max = 400) { return typeof text === "string" ? text.slice(0, max) : ""; }
function cleanUrl(url, host) {
  try {
    const value = new URL(url);
    return value.protocol === "https:" && value.hostname === host ? value.href : null;
  } catch { return null; }
}
function statusOfRun(run) {
  if (run.status === "in_progress") return "running";
  if (run.status === "queued" || run.status === "pending" || run.status === "waiting") return "queued";
  if (run.conclusion === "success") return "completed";
  if (run.conclusion === "failure" || run.conclusion === "timed_out") return "failed";
  if (run.conclusion === "cancelled") return "cancelled";
  return "unknown";
}
export class ProjectHub {
  constructor(core, agentRuntime, { env = process.env, fetchImpl = fetch, now = () => Date.now() } = {}) {
    this.core = core;
    this.ai = agentRuntime;
    this.env = env;
    this.fetchImpl = fetchImpl;
    this.now = now;
    core.data.projects ??= {};
    core.data.externalProjects ??= {};
    this.repoCache = new Map();
  }
  sources() {
    const repos = repoSpec(this.env);
    const codexEnabled = this.env.OAGENT_ENABLE_CODEX_CLOUD_SYNC === "1";
    const codexVerified = codexEnabled && Object.values(this.core.data.externalProjects).some(p => this.now() - p.syncedAt < 120000);
    const githubVerified = [...this.repoCache.values()].some(v => this.now() - v.at < 120000);
    return [
      {
        id: "oagent", label: "O-AGENT", status: "available",
        capabilities: ["list_projects", "send_prompt", "view_agent_messages"],
        limitation: "Owned conversations only; external provider credentials and quota still required for AI replies.",
      },
      {
        id: "github", label: "GitHub", status: repos.length ? (githubVerified ? "connected" : "configured_unverified") : "requires_setup",
        capabilities: repos.length ? ["list_projects", "view_workflow_runs", "view_pull_requests", "open_provider"] : [],
        limitation: "Read-only; GitHub workflow status does not reveal live agent browser screens or give provider approval control.",
      },
      {
        id: "codex_cloud", label: "Codex Cloud", status: codexEnabled ? (codexVerified ? "connected" : "configured_unverified") : "requires_setup",
        capabilities: codexEnabled ? ["list_cloud_tasks", "open_provider", "request_new_cloud_task_with_approval"] : [],
        limitation: "Existing cloud tasks are read-only; a NEW task can be submitted with explicit approval via authenticated Codex CLI. No live browser viewport or Work chat access.",
      },
      {
        id: "chatgpt_work", label: "ChatGPT Work", status: "unsupported",
        capabilities: [],
        limitation: "No verified third-party API to mirror existing Work chats, cloud browser screens, or in-product permissions.",
      },
    ];
  }
  async fetchGithub(path) {
    const headers = {
      "accept": "application/vnd.github+json",
      "user-agent": "O-AGENT-project-hub",
      "x-github-api-version": "2022-11-28",
    };
    if (this.env.OAGENT_GITHUB_TOKEN) headers.authorization = "Bearer " + this.env.OAGENT_GITHUB_TOKEN;
    let response;
    try {
      response = await this.fetchImpl("https://api.github.com/" + path, {
        headers,
        signal: AbortSignal.timeout(8000),
      });
    } catch { throw new Error("Cannot contact GitHub REST API"); }
    if (!response.ok) {
      if (response.status === 401 || response.status === 403) throw new Error("GitHub access denied or rate-limited (" + response.status + ")");
      if (response.status === 404) throw new Error("Repository unavailable or not accessible");
      throw new Error("GitHub returned HTTP " + response.status);
    }
    return response.json();
  }
  async githubProject(repo) {
    const cached = this.repoCache.get(repo);
    if (cached && this.now() - cached.at < 30000) return cached.value;
    const spec = encodeURI(repo);
    const [info, workflow, pulls] = await Promise.all([
      this.fetchGithub("repos/" + spec),
      this.fetchGithub("repos/" + spec + "/actions/runs?per_page=8"),
      this.fetchGithub("repos/" + spec + "/pulls?state=all&sort=updated&per_page=6"),
    ]);
    const runs = (Array.isArray(workflow.workflow_runs) ? workflow.workflow_runs : []).map(run => ({
      id: String(run.id),
      title: shorten(run.name || run.display_title || "Workflow", 120),
      status: statusOfRun(run),
      rawStatus: run.status || "",
      conclusion: run.conclusion || null,
      updatedAt: run.updated_at || null,
      url: cleanUrl(run.html_url, "github.com"),
    }));
    const prItems = (Array.isArray(pulls) ? pulls : []).map(p => ({
      id: String(p.number), title: shorten(p.title, 160),
      status: p.state === "open" ? "open" : (p.merged_at ? "merged" : "closed"),
      updatedAt: p.updated_at || null,
      url: cleanUrl(p.html_url, "github.com"),
    }));
    const result = {
      id: "github:" + repo,
      source: "github",
      title: shorten(info.name || repo.split("/")[1], 120),
      description: shorten(info.description, 300),
      url: cleanUrl(info.html_url, "github.com"),
      updatedAt: info.pushed_at || info.updated_at || null,
      state: runs.length ? runs[0].status : "no_runs",
      sourceRef: repo,
      capabilities: ["view_workflow_runs", "view_pull_requests", "open_provider"],
      runs,
      pullRequests: prItems,
      liveBrowser: false,
      control: "read_only",
    };
    this.repoCache.set(repo, { at: this.now(), value: result });
    return result;
  }
  async list() {
    const local = Object.values(this.core.data.projects).map(p => this.localView(p));
    const codex = Object.values(this.core.data.externalProjects).map(p => {
      const fresh = this.now() - p.syncedAt < 120000;
      return { ...p, state: fresh ? p.state : "stale", stale: !fresh };
    });
    const repos = repoSpec(this.env);
    const results = await Promise.all(repos.map(async repo => {
      try { return { project: await this.githubProject(repo) }; }
      catch (e) { return { error: { repo, message: e.message } }; }
    }));
    return {
      projects: [...local, ...codex, ...results.filter(r => r.project).map(r => r.project)],
      sources: this.sources(),
      sourceErrors: results.filter(r => r.error).map(r => r.error),
      updatedAt: new Date(this.now()).toISOString(),
    };
  }
  localView(project) {
    return {
      id: project.id, source: "oagent", title: project.title,
      description: project.description || "", state: "ready",
      updatedAt: new Date(project.updatedAt).toISOString(),
      capabilities: ["send_prompt", "view_agent_messages"],
      control: "oagent_only", liveBrowser: false,
      threadId: project.threadId || null,
    };
  }
  async details(id) {
    const local = this.core.data.projects[id];
    if (local) return { project: this.localView(local), thread: local.threadId ? this.ai.getThread(local.threadId) : null };
    if (id.startsWith("github:")) {
      const spec = id.slice(7);
      if (!repoSpec(this.env).includes(spec)) throw new DomainError(404, "GitHub project is not configured");
      return { project: await this.githubProject(spec), thread: null };
    }
    const imported = this.core.data.externalProjects[id];
    if (imported) return { project: { ...imported, stale: this.now() - imported.syncedAt >= 120000 }, thread: null };
    throw new DomainError(404, "Project not found");
  }
  create(body) {
    const title = safeTitle(body?.title, "project title", 120);
    const description = body.description == null ? "" : shorten(body.description, 500);
    if (Object.keys(this.core.data.projects).length >= 100) throw new DomainError(409, "Project limit reached");
    const p = { id: randomUUID(), title, description, threadId: null, createdAt: this.now(), updatedAt: this.now() };
    this.core.data.projects[p.id] = p;
    this.core.commit("project.created", { projectId: p.id });
    return this.localView(p);
  }
  async send(id, body) {
    const project = this.core.data.projects[id];
    if (!project) throw new DomainError(404, "Only O-AGENT-owned projects support prompt submission");
    // No pretend injection into GitHub, Codex, ChatGPT Work or other providers.
    const agentId = body?.agentId || "navigator";
    const thread = await this.ai.send({ agentId, threadId: project.threadId, message: body?.message });
    project.threadId = thread.id;
    project.updatedAt = this.now();
    this.core.commit("project.message.completed", { projectId: id, threadId: thread.id });
    return { project: this.localView(project), thread };
  }
  requestCodexTask(body, requestKey) {
    if (this.env.OAGENT_ENABLE_CODEX_CLOUD_SYNC !== "1") {
      throw new DomainError(403, "Codex Cloud connector must be enabled explicitly");
    }
    const workerId = safeTitle(body?.workerId, "workerId", 100);
    const worker = this.core.snapshot().workers.find(w => w.id === workerId);
    if (!worker || worker.status !== "online") throw new DomainError(409, "Codex CLI laptop worker must be online");
    // This is a NEW Codex Cloud task, not a follow-up to an existing session.
    // The operator must explicitly approve its exact environment and prompt.
    return this.core.createTask({
      workerId,
      kind: "codex_cloud_submit",
      environmentId: body?.environmentId,
      prompt: body?.prompt,
    }, requestKey);
  }

  // Codex metadata is accepted only from the authenticated worker route.
  publishCodex(workerId, body) {
    if (this.env.OAGENT_ENABLE_CODEX_CLOUD_SYNC !== "1") {
      throw new DomainError(403, "Codex Cloud synchronization is disabled");
    }
    if (typeof workerId !== "string" || !this.core.data.workers[workerId]) throw new DomainError(403, "Unknown worker");
    if (!body || !Array.isArray(body.tasks) || body.tasks.length > 20) throw new DomainError(400, "Expected up to 20 Codex Cloud tasks");
    const stamp = this.now();
    const changed = [];
    for (const item of body.tasks) {
      const taskId = safeTitle(item.id, "Codex task ID", 120);
      if (!/^[\w-]{4,120}$/.test(taskId)) throw new DomainError(400, "Invalid Codex task ID");
      const title = safeTitle(item.title || item.summary || taskId, "Codex task title", 180);
      const projectId = "codex:" + workerId + ":" + taskId;
      const next = {
        id: projectId, source: "codex_cloud", title,
        description: shorten(item.summary, 300), sourceRef: taskId,
        state: shorten(item.status || "unknown", 40), updatedAt: item.updated_at || null,
        environmentId: typeof item.environment_id === "string" ? item.environment_id.slice(0, 120) : null,
        url: cleanUrl(item.url, "chatgpt.com"), workerId,
        syncedAt: stamp, control: "read_only",
        capabilities: ["open_provider", "view_cloud_task_status"],
        liveBrowser: false,
      };
      const old = this.core.data.externalProjects[projectId];
      if (!old || old.title !== next.title || old.state !== next.state || old.description !== next.description) changed.push(projectId);
      this.core.data.externalProjects[projectId] = next;
    }
    // Bound persisted data; leave out of scope records only if a new sync supplies more.
    const entries = Object.entries(this.core.data.externalProjects);
    if (entries.length > 200) {
      for (const [id] of entries.sort((a,b) => a[1].syncedAt - b[1].syncedAt).slice(0, entries.length - 200)) delete this.core.data.externalProjects[id];
    }
    this.core.commit("provider.codex.synced", { workerId, count: body.tasks.length, changed: changed.slice(0,20) });
    return { accepted: body.tasks.length, changed: changed.length };
  }
}
