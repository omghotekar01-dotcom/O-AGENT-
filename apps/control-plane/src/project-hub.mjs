import { randomUUID, createHash } from "node:crypto";
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
    core.data.codexLocalProjects ??= {};
    core.data.codexLocalSync ??= {};
    // Opting out must stop exposing previously persisted session previews and
    // cwd paths, not merely stop subsequent polling.
    if (env.OAGENT_ENABLE_CODEX_LOCAL_SYNC !== "1" &&
        (Object.keys(core.data.codexLocalProjects).length || Object.keys(core.data.codexLocalSync).length)) {
      core.data.codexLocalProjects = {};
      core.data.codexLocalSync = {};
      core.commit("provider.codex_local.disabled");
    }
    this.repoCache = new Map();
  }
  sources() {
    const repos = repoSpec(this.env);
    const codexEnabled = this.env.OAGENT_ENABLE_CODEX_CLOUD_SYNC === "1";
    const localCodexEnabled = this.env.OAGENT_ENABLE_CODEX_LOCAL_SYNC === "1";
    const localCodexVerified = localCodexEnabled && Object.values(this.core.data.codexLocalSync).some(at => this.now() - at < 120000);
    const codexVerified = codexEnabled && Object.values(this.core.data.externalProjects).some(p => this.now() - p.syncedAt < 120000);
    const githubVerified = [...this.repoCache.values()].some(v => this.now() - v.at < 120000);
    const workers = this.core.snapshot().workers.filter(w => w.status === "online");
    const hasCapability = kind => workers.some(w => w.capabilities?.includes(kind));
    const ai = typeof this.ai?.status === "function" ? this.ai.status() : null;
    const apiStatus = provider => ai?.provider !== provider || !ai?.configured
      ? "requires_setup"
      : ai.health === "connected" ? "connected" : "configured_unverified";
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
        id: "codex_cli", label: "Codex CLI / IDE", 
        status: localCodexEnabled ? (localCodexVerified ? "connected" : "configured_unverified") : "requires_setup",
        capabilities: localCodexEnabled ? ["list_local_workspaces", "view_session_metadata", "request_supervised_turn", "view_turn_events", "decide_permission_requests"] : [],
        limitation: "Saved CLI/IDE threads support newly approved Codex turns and event updates, with controlled permission requests. This does not inject into an independent running CLI window or mirror ChatGPT browser screens.",
      },
      {
        id: "openai_api", label: "OpenAI API", status: apiStatus("openai"),
        capabilities: ai?.provider === "openai" && ai?.configured
          ? ["send_prompt_in_oagent", "view_oagent_conversations", "improve_prompt"] : [],
        limitation: "O-AGENT-owned API conversations only. Does not mirror private ChatGPT Projects, Work browser sessions or existing Codex IDE chats. Requires an independently billed API key and quota.",
      },
      {
        id: "gemini_api", label: "Google Gemini API", status: apiStatus("gemini"),
        capabilities: ai?.provider === "gemini" && ai?.configured
          ? ["send_prompt_in_oagent", "view_oagent_conversations", "improve_prompt"] : [],
        limitation: "Uses O-AGENT-owned Gemini API conversations only. It cannot read existing consumer Gemini website sessions or browser screens. Requires Google AI Studio API key and quota.",
      },
      {
        id: "claude_api", label: "Anthropic Claude API", status: apiStatus("anthropic"),
        capabilities: ai?.provider === "anthropic" && ai?.configured
          ? ["send_prompt_in_oagent", "view_oagent_conversations", "improve_prompt"] : [],
        limitation: "Messages API for O-AGENT-owned conversations. Does not read arbitrary claude.ai chats or Claude Code IDE sessions.",
      },
      {
        id: "copilot_sdk", label: "GitHub Copilot SDK",
        status: hasCapability("copilot_sdk_turn") ? "configured_unverified" : "requires_setup",
        capabilities: hasCapability("copilot_sdk_turn")
          ? ["request_supervised_turn","view_turn_events","decide_permission_requests"] : [],
        limitation: "A separate Copilot SDK runtime and authenticated session must be installed and tested. GitHub repository read access is not Copilot session access.",
      },
      {
        id: "claude_code", label: "Claude Agent SDK",
        status: hasCapability("claude_agent_turn") ? "configured_unverified" : "requires_setup",
        capabilities: hasCapability("claude_agent_turn")
          ? ["request_supervised_turn","view_turn_events","decide_permission_requests"] : [],
        limitation: "Requires a signed-in, enrolled Claude Code/Agent SDK runtime and an explicit session permission bridge. Not currently reading existing sessions.",
      },
      {
        id: "cursor", label: "Cursor local IDE", status: "not_implemented",
        capabilities: [],
        limitation: "Cursor has an official CLI with headless and session operations; O-AGENT does not yet own or control a Cursor CLI session or active IDE tab.",
      },
      {
        id: "vscode", label: "VS Code Workspace Companion",
        status: hasCapability("vscode_workspace_files") ? "connected" :
          hasCapability("vscode_open_file") ? "configured_unverified" : "requires_setup",
        capabilities: hasCapability("vscode_workspace_files")
          ? ["browse_enrolled_workspace", "read_allowed_text_files", "create_text_file",
             "rename_text_file", "move_to_trash", "review_and_save_changes",
             "monitor_git_and_unsaved_names", "request_approved_open_file"]
          : hasCapability("vscode_open_file")
            ? ["workspace_inventory","request_approved_open_file","local_confirm_open_file"]
            : [],
        limitation: "Only an explicitly enrolled VS Code folder is accessible. File modifications require a 30-minute permission locally plus phone/web approval. Does not control native Copilot Chat, Claude extension chats, or arbitrary other IDEs.",
      },
      {
        id: "chatgpt_work", label: "ChatGPT Work / website", status: "unsupported",
        capabilities: [],
        limitation: "No verified third-party API to mirror arbitrary existing ChatGPT project chats, managed cloud browsers, or all in-product UI and approvals.",
      },
    ];
  }
  /**
   * Owner-only remote command center. Values are derived exclusively from
   * authenticated worker syncs and actual persisted task/approval state.
   * A saved Codex thread is never mislabeled as an actively running IDE tab.
   */
  remoteOverview() {
    const now = this.now();
    const machines = this.core.snapshot().workers.map(w => ({
      id: w.id, name: w.name, status: w.status, lastSeenAt: w.lastSeenAt,
      capabilities: (w.capabilities ?? []).filter(x => typeof x === "string"),
    }));
    const sessions = Object.values(this.core.data.codexLocalProjects).flatMap(p => {
      const synced = now - p.syncedAt < 120000;
      const machine = machines.find(w => w.id === p.workerId);
      return (p.sessions || []).map(s => ({
        projectId: p.id, projectTitle: p.title, cwd: p.cwd,
        workerId: p.workerId, sessionId: s.id, title: s.title,
        lastKnownState: s.state, updatedAt: s.updatedAt,
        syncFresh: synced, workerOnline: machine?.status === "online",
        // Last-known process state is not proof of a currently interactive tab.
        observedState: synced ? "saved_session" : "stale_session",
      }));
    }).slice(0, 80);
    const taskState = this.core.snapshot().tasks
      .filter(t => ["codex_cli_turn", "codex_cloud_submit",
        "claude_agent_turn", "copilot_sdk_turn", "vscode_open_file"].includes(t.kind))
      .slice(0, 70);
    const runs = taskState.map(t => {
      const approvals = Object.values(t.approvals ?? {}).filter(a =>
        a.state === "pending" && a.expiresAt > now && t.status === "running")
        .map(a => ({ id: a.id, kind: a.kind, description: a.description,
          expiresAt: a.expiresAt }));
      const p = t.parameters ?? {};
      const related = sessions.find(s => s.sessionId === p.sessionId &&
        s.projectId === p.projectId);
      const last = t.updates?.at(-1);
      return {
        id: t.id, kind: t.kind, status: t.status, workerId: t.workerId,
        projectId: p.projectId ?? null, sessionId: p.sessionId ?? null,
        cwd: p.cwd ?? null, mode: p.mode ?? null,
        sessionTitle: related?.title ?? null,
        projectTitle: related?.projectTitle ?? null,
        promptPreview: shorten(p.prompt, 220),
        createdAt: t.createdAt, updatedAt: t.updatedAt,
        updateCount: t.nextUpdate ?? t.updates?.length ?? 0,
        latestEvent: last ? { type: last.type, text: shorten(last.text, 400),
          at: last.at } : null,
        pendingApprovals: approvals,
        error: shorten(t.error, 300) || null,
        // Only a supervised O-AGENT turn can be resumed in our mobile console.
        canOpenBridgeTask: ["claude_agent_turn","copilot_sdk_turn"].includes(t.kind),
        canOpenVscodeTask: t.kind === "vscode_open_file",
        canOpenSession: t.kind === "codex_cli_turn" &&
          typeof p.projectId === "string" && typeof p.sessionId === "string",
      };
    });
    return {
      generatedAt: new Date(now).toISOString(),
      machines, sessions, runs,
      sources: this.sources().map(s => ({
        id: s.id, label: s.label, status: s.status,
        capabilities: s.capabilities, limitation: s.limitation,
      })),
      activeRuns: runs.filter(r => ["waiting_for_approval", "queued", "running"].includes(r.status)).length,
      pendingApprovals: runs.filter(r => r.status === "waiting_for_approval").length +
        runs.reduce((n, r) => n + r.pendingApprovals.length, 0),
      screenStreaming: { supported: false, reason:
        "No explicitly consented Windows capture/streaming agent has been enrolled." },
    };
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
    const codexLocal = Object.values(this.core.data.codexLocalProjects).map(p => {
      const stale = this.now() - p.syncedAt >= 120000;
      return { ...p, state: stale ? "stale" : p.state, stale };
    });
    const repos = repoSpec(this.env);
    const results = await Promise.all(repos.map(async repo => {
      try { return { project: await this.githubProject(repo) }; }
      catch (e) { return { error: { repo, message: e.message } }; }
    }));
    return {
      projects: [...codexLocal, ...local, ...codex, ...results.filter(r => r.project).map(r => r.project)],
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
    const localCodex = this.core.data.codexLocalProjects[id];
    if (localCodex) {
      const stale = this.now() - localCodex.syncedAt >= 120000;
      return { project: { ...localCodex, state: stale ? "stale" : localCodex.state, stale }, thread: null };
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
  requestLocalCodexHistory(body, requestKey) {
    if (this.env.OAGENT_ENABLE_CODEX_LOCAL_SYNC !== "1")
      throw new DomainError(403, "Codex saved conversation connector is disabled");
    const projectId = safeTitle(body?.projectId, "Codex project ID", 160);
    const sessionId = safeTitle(body?.sessionId, "Codex conversation ID", 120);
    const project = this.core.data.codexLocalProjects[projectId];
    if (!project || !project.sessions.some(s => s.id === sessionId))
      throw new DomainError(404, "This saved conversation is not among your laptop's discovered projects. Refresh the project list.");
    if (this.now() - project.syncedAt >= 120000)
      throw new DomainError(409, "Codex conversation list is stale. Check that O-AGENT is running on the laptop and refresh.");
    const worker = this.core.snapshot().workers.find(w => w.id === project.workerId);
    if (!worker || worker.status !== "online")
      throw new DomainError(409, "Your laptop is offline. Connect it to O-AGENT before loading conversation history.");
    const existing = Object.values(this.core.data.tasks).find(t =>
      t.kind === "codex_cli_history" && t.parameters?.sessionId === sessionId &&
      t.workerId === project.workerId &&
      ["queued","running"].includes(t.status));
    if (existing) return existing;
    return this.core.createTask({
      workerId: project.workerId, kind:"codex_cli_history",projectId,sessionId,
    },requestKey);
  }
  requestLocalCodexTurn(body, requestKey) {
    if (this.env.OAGENT_ENABLE_CODEX_LOCAL_SYNC !== "1") throw new DomainError(403, "Codex CLI connector disabled");
    const projectId = safeTitle(body?.projectId, "Codex project ID", 160);
    const sessionId = safeTitle(body?.sessionId, "Codex session ID", 120);
    const project = this.core.data.codexLocalProjects[projectId];
    if (!project) throw new DomainError(404, "Codex workspace not found; refresh real CLI history");
    if (this.now() - project.syncedAt >= 120000) throw new DomainError(409, "Codex workspace sync is stale; refresh the CLI worker");
    if (!project.sessions.some(session => session.id === sessionId)) throw new DomainError(404, "Session does not belong to selected workspace");
    const worker = this.core.snapshot().workers.find(w => w.id === project.workerId);
    if (!worker || worker.status !== "online") throw new DomainError(409, "Codex CLI laptop worker is offline");
    const existing = Object.values(this.core.data.tasks).find(t =>
      t.kind === "codex_cli_turn" && t.parameters?.sessionId === sessionId &&
      !["completed","failed","rejected","cancelled","interrupted"].includes(t.status));
    if (existing && existing.requestKey !== requestKey) throw new DomainError(409, "A Codex turn is already active or awaiting approval for this session");
    return this.core.createTask({
      workerId: project.workerId, kind: "codex_cli_turn",
      projectId, sessionId, cwd: project.cwd,
      prompt: body.prompt, mode: body.mode || "read_only",
    }, requestKey);
  }

  confirmLocalCodexTurn(body, requestKey) {
    // The owner already reviewed and accepted the exact immutable prompt in
    // the phone confirmation dialog. This is a single, idempotent consent
    // transaction; project-edit tool approvals remain individually required.
    if (body?.consent !== "authorize-exact-prompt")
      throw new DomainError(400, "You must explicitly confirm the exact Codex instruction");
    const task = this.requestLocalCodexTurn(body, requestKey);
    if (task.status === "waiting_for_approval") return this.core.decide(task.id, true);
    return task; // Idempotent replay of an already approved or terminal task.
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

  // Read-only local history from an explicitly opted-in, authenticated worker.
  publishCodexLocal(workerId, body) {
    if (this.env.OAGENT_ENABLE_CODEX_LOCAL_SYNC !== "1") {
      throw new DomainError(403, "Codex CLI local session sync is disabled");
    }
    if (!this.core.data.workers[workerId]) throw new DomainError(403, "Unknown worker");
    if (!body || !Array.isArray(body.sessions) || body.sessions.length > 80) {
      throw new DomainError(400, "Expected at most 80 Codex CLI sessions");
    }
    const grouped = new Map();
    const stamp = this.now();
    for (const item of body.sessions) {
      const sessionId = safeTitle(item?.id, "Codex session ID", 120);
      if (!/^[\w-]{8,120}$/.test(sessionId)) throw new DomainError(400, "Invalid Codex session ID");
      const cwd = safeTitle(item.cwd, "Codex working directory", 600);
      if (!/^(?:[A-Za-z]:[\\/]|\/)/.test(cwd) || /[\x00-\x1f]/.test(cwd)) {
        throw new DomainError(400, "Codex session working directory must be absolute");
      }
      const hash = createHash("sha256").update(workerId + "|" + cwd.toLowerCase()).digest("hex").slice(0, 24);
      const id = "codex-local:" + workerId + ":" + hash;
      if (!grouped.has(id)) grouped.set(id, { id, cwd, sessions: [] });
      const state = ["active", "idle", "notLoaded", "systemError"].includes(item.state)
        ? item.state : "unknown";
      const session = {
        id: sessionId,
        title: shorten(item.title, 180) || "Codex session",
        state, activeFlags: Array.isArray(item.activeFlags)
          ? item.activeFlags.filter(x => x === "waitingOnApproval" || x === "waitingOnUserInput").slice(0, 2) : [],
        updatedAt: typeof item.updatedAt === "string" && !Number.isNaN(Date.parse(item.updatedAt)) ? item.updatedAt : null,
        modelProvider: shorten(item.modelProvider, 80) || null,
      };
      grouped.get(id).sessions.push(session);
    }
    const fresh = {};
    for (const group of grouped.values()) {
      group.sessions.sort((a, b) => (b.updatedAt || "").localeCompare(a.updatedAt || ""));
      const latest = group.sessions[0];
      const cwd = group.cwd;
      const folder = cwd.replace(/[\\/]+$/, "").split(/[\\/]/).pop() || cwd;
      fresh[group.id] = {
        id: group.id, source: "codex_cli", sourceRef: cwd,
        title: shorten(folder, 120),
        description: "Codex CLI / IDE workspace · " + group.sessions.length + " saved session(s)",
        cwd, sessions: group.sessions, workerId,
        updatedAt: latest?.updatedAt || null, syncedAt: stamp,
        // An independent scanner cannot determine what another active Codex
        // process is currently doing. No false running indicator.
        state: "history_available", liveBrowser: false,
        control: "approval_gated", capabilities: ["view_session_metadata", "read_saved_conversation", "request_supervised_turn", "view_turn_events", "decide_permission_requests"],
      };
    }
    // A successful empty sync clears previous sessions for this worker.
    for (const [id, project] of Object.entries(this.core.data.codexLocalProjects)) {
      if (project.workerId === workerId) delete this.core.data.codexLocalProjects[id];
    }
    Object.assign(this.core.data.codexLocalProjects, fresh);
    this.core.data.codexLocalSync[workerId] = stamp;
    this.core.commit("provider.codex_local.synced", { workerId, projectCount: grouped.size, sessionCount: body.sessions.length });
    return { projectCount: grouped.size, sessionCount: body.sessions.length };
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
