import { createServer } from "node:http";
import { readFileSync, writeFileSync, renameSync, mkdirSync, existsSync } from "node:fs";
import { resolve, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { timingSafeEqual } from "node:crypto";
import { ControlPlane, DomainError } from "./core.mjs";
import { AgentRuntime } from "./agent-runtime.mjs";
import { ProjectHub } from "./project-hub.mjs";
import { AccountHub } from "./account-hub.mjs";
import { PublicAuth } from "./public-auth.mjs";
import { ScreenShare } from "./screen-share.mjs";
import { RemoteInput } from "./remote-input.mjs";
import { VscodePresence } from "./vscode-presence.mjs";
import { VscodeFileRelay } from "./vscode-file-relay.mjs";
import { PushHub } from "./push-hub.mjs";

const apiToken = process.env.OAGENT_API_TOKEN ?? "";
const workerToken = process.env.OAGENT_WORKER_TOKEN ?? "";
if (apiToken.length < 24 || workerToken.length < 24 || apiToken === workerToken) {
  throw new Error("Set distinct OAGENT_API_TOKEN and OAGENT_WORKER_TOKEN (each at least 24 characters)");
}
const host = process.env.HOST || "127.0.0.1";
const port = Number(process.env.PORT || 8787);
const dbPath = resolve(process.env.OAGENT_DATA_FILE || "./.local/oagent-data.json");
const localDir = dirname(fileURLToPath(import.meta.url));
const publicDir = resolve(localDir, "../public");
function persist(data) {
  mkdirSync(dirname(dbPath), { recursive: true });
  const temp = dbPath + ".tmp";
  writeFileSync(temp, JSON.stringify(data, null, 2), { mode: 0o600 });
  renameSync(temp, dbPath);
}
const initial = existsSync(dbPath) ? JSON.parse(readFileSync(dbPath, "utf8")) : {};
const core = new ControlPlane(initial, persist);
const agentRuntime = new AgentRuntime(core);
const projectHub = new ProjectHub(core, agentRuntime);
const accountHub = new AccountHub(core);
const publicAuth = new PublicAuth(core);
const screenShare = new ScreenShare();
const remoteInput = new RemoteInput({ captureFresh: () => screenShare.status().fresh });
const vscodePresence = new VscodePresence();
const vscodeFileRelay = new VscodeFileRelay();
const pushHub = new PushHub(core, accountHub);
const JSON_HEADERS = { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", "x-content-type-options": "nosniff" };
function send(res, code, payload) {
  res.writeHead(code, JSON_HEADERS);
  res.end(JSON.stringify(payload));
}
function authorized(req, secret) {
  const bearer = req.headers.authorization;
  if (typeof bearer !== "string" || !bearer.startsWith("Bearer ")) return false;
  const actual = Buffer.from(bearer.slice(7));
  const expected = Buffer.from(secret);
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}
function readJson(req, maxLength = 32768) {
  return new Promise((resolveBody, reject) => {
    let body = "";
    req.on("data", chunk => {
      body += chunk;
      if (body.length > maxLength) {
        reject(new DomainError(413, "Request body too large"));
        req.destroy();
      }
    });
    req.on("end", () => {
      try {
        const obj = body ? JSON.parse(body) : {};
        if (!obj || typeof obj !== "object" || Array.isArray(obj)) throw new Error("Expected object");
        resolveBody(obj);
      } catch { reject(new DomainError(400, "Invalid JSON object")); }
    });
    req.on("error", reject);
  });
}
function readBinary(req, maxBytes) {
  return new Promise((resolveData, reject) => {
    const chunks = [];
    let size = 0;
    req.on("data", chunk => {
      size += chunk.length;
      if (size > maxBytes) {
        reject(new DomainError(413, "Screen frame too large"));
        req.destroy();
      } else chunks.push(chunk);
    });
    req.on("end", () => resolveData(Buffer.concat(chunks)));
    req.on("error", reject);
  });
}
function staticFile(res, filename, type) {
  const bytes = readFileSync(join(publicDir, filename));
  res.writeHead(200, { "content-type": type, "cache-control": "no-store", "x-content-type-options": "nosniff", "content-security-policy": "default-src 'self'; connect-src 'self'; script-src 'self'; style-src 'self'; base-uri 'none'; object-src 'none'; frame-ancestors 'none'" });
  res.end(bytes);
}
const server = createServer(async (req, res) => {
  try {
    const url = new URL(req.url ?? "/", "http://localhost");
    const path = url.pathname;
    if (req.method === "GET" && path === "/health") return send(res, 200, { status: "ok", service: "oagent-control-plane" });
    if (req.method === "GET" && path === "/") return staticFile(res, "index.html", "text/html; charset=utf-8");
    if (req.method === "GET" && path === "/screen-capture") return staticFile(res, "screen-capture.html", "text/html; charset=utf-8");
    if (req.method === "GET" && path === "/screen-capture.js") return staticFile(res, "screen-capture.js", "text/javascript; charset=utf-8");
    if (req.method === "GET" && path === "/screen-capture.css") return staticFile(res, "screen-capture.css", "text/css; charset=utf-8");
    if (req.method === "GET" && path === "/dashboard.css") return staticFile(res, "dashboard.css", "text/css; charset=utf-8");
    if (req.method === "GET" && path === "/dashboard.js") return staticFile(res, "dashboard.js", "text/javascript; charset=utf-8");
    // Anonymous email/password endpoints have per-address throttling.
    if (req.method === "GET" && path === "/api/auth/config") return send(res, 200, publicAuth.config());
    if (req.method === "POST" && path.startsWith("/api/auth/")) {
      const action = path.slice("/api/auth/".length);
      const ip = req.socket.remoteAddress || "unknown";
      if (["register", "verify", "resend", "login", "forgot", "reset"].includes(action)) {
        publicAuth.throttle(ip, action);
        const body = await readJson(req, 4096);
        if (action === "register") return send(res, 201, await publicAuth.register(body));
        if (action === "verify") return send(res, 200, publicAuth.verify(body));
        if (action === "resend") return send(res, 200, await publicAuth.resend(body));
        if (action === "login") return send(res, 200, await publicAuth.login(body));
        if (action === "forgot") return send(res, 200, await publicAuth.forgot(body));
        if (action === "reset") return send(res, 200, await publicAuth.reset(body));
      }
    }
    // Joining requires a previously authorized one-time invitation.
    if (req.method === "POST" && path === "/api/accounts/claim") {
      publicAuth.throttle(req.socket.remoteAddress || "unknown", "claim");
      return send(res, 201, accountHub.claimInvitation(await readJson(req, 4096)));
    }
    const isWorkerRoute = path.startsWith("/api/workers/");
    const owner = authorized(req, apiToken);
    const worker = isWorkerRoute && authorized(req, workerToken);
    const authHeader = req.headers.authorization ?? "";
    const member = !owner && !worker && typeof authHeader === "string" &&
      authHeader.startsWith("Bearer ") ?
        (publicAuth.authenticate(authHeader.slice(7)) || accountHub.authenticate(authHeader.slice(7))) : null;
    if (isWorkerRoute ? !worker : (!owner && !member)) throw new DomainError(401, "Invalid authorization token");
    const userId = owner ? "owner" : member?.id;
    if (req.method === "POST" && path === "/api/auth/logout") {
      return send(res, 200, publicAuth.logout(authHeader.slice(7)));
    }

    // View-only live preview is a separate owner-only capability. A random
    // short-lived capture lease is additionally required to upload frames.
    if (path.startsWith("/api/screen/")) {
      if (!owner) throw new DomainError(403, "Only the owner can view or share a screen");
      if (req.method === "GET" && path === "/api/screen/status")
        return send(res, 200, screenShare.status());
      if (req.method === "POST" && path === "/api/screen/start")
        return send(res, 201, screenShare.start());
      if (req.method === "POST" && path === "/api/screen/stop") {
        remoteInput.stop();
        return send(res, 200, screenShare.stop());
      }
      if (req.method === "POST" && path === "/api/screen/frame") {
        const image = await readBinary(req, ScreenShare.maxFrameBytes);
        return send(res, 200, screenShare.publish(
          req.headers["x-oagent-capture-token"], image));
      }
      if (req.method === "GET" && path === "/api/screen/frame") {
        const image = screenShare.frame();
        res.writeHead(200, {
          "content-type": "image/jpeg",
          "cache-control": "no-store",
          "x-content-type-options": "nosniff",
          "x-oagent-frame-sequence": String(image.sequence),
        });
        res.end(image.bytes);
        return;
      }
      throw new DomainError(404, "Unknown screen-share endpoint");
    }
    if (req.method === "GET" && path === "/api/me") {
      return send(res, 200, owner
        ? { id: "owner", displayName: "Workspace owner", role: "owner", vaultReady: accountHub.vaultReady }
        : { ...member, vaultReady: accountHub.vaultReady });
    }
    if (owner && req.method === "POST" && path === "/api/accounts/invitations") {
      return send(res, 201, accountHub.createInvitation(await readJson(req, 4096)));
    }
    if (owner && req.method === "GET" && path === "/api/accounts/members") {
      return send(res, 200, { members: accountHub.members() });
    }
    const revokeMember = path.match(/^\/api\/accounts\/members\/([0-9a-f-]+)$/);
    if (owner && req.method === "DELETE" && revokeMember) {
      const revoked = accountHub.revokeMember(revokeMember[1]);
      publicAuth.revokeUser(revokeMember[1]);
      return send(res, 200, revoked);
    }
    if (!isWorkerRoute && path.startsWith("/api/account/")) {
      if (path === "/api/account/push") {
      if (req.method === "GET") return send(res, 200, pushHub.status(userId));
      if (req.method === "POST") return send(res, 201,
        pushHub.register(userId, await readJson(req, 8192)));
    }
    const pushDelete = path.match(/^\/api\/account\/push\/devices\/([0-9a-f-]{36})$/);
    if (req.method === "DELETE" && pushDelete) {
      return send(res, 200, pushHub.unregister(userId, pushDelete[1]));
    }
    if (req.method === "GET" && path === "/api/account/connections") {
        return send(res, 200, accountHub.listConnections(userId));
      }
      const connectionPath = path.match(/^\/api\/account\/connections\/(openai|anthropic|gemini)$/);
      if (connectionPath && req.method === "PUT") {
        return send(res, 200, accountHub.saveConnection(userId, connectionPath[1], await readJson(req, 4096)));
      }
      if (connectionPath && req.method === "DELETE") {
        return send(res, 200, accountHub.deleteConnection(userId, connectionPath[1]));
      }
      const verifyPath = path.match(/^\/api\/account\/connections\/(openai|anthropic|gemini)\/verify$/);
      if (verifyPath && req.method === "POST") {
        return send(res, 200, await accountHub.verifyConnection(userId, verifyPath[1]));
      }
      // Per-account Cursor Cloud Agents v1. These routes are deliberately
      // inside the personal-account scope, never the owner machine/task scope.
      if (path === "/api/account/cursor") {
        if (req.method === "GET") return send(res, 200, accountHub.cursorStatus(userId));
        if (req.method === "PUT") return send(res, 200,
          accountHub.connectCursor(userId, await readJson(req, 4096)));
        if (req.method === "DELETE") return send(res, 200, accountHub.disconnectCursor(userId));
      }
      if (req.method === "POST" && path === "/api/account/cursor/verify") {
        return send(res, 200, await accountHub.verifyCursor(userId));
      }
      if (req.method === "GET" && path === "/api/account/cursor/agents") {
        return send(res, 200, await accountHub.cursorAgents(userId));
      }
      if (req.method === "POST" && path === "/api/account/cursor/agents") {
        return send(res, 201, await accountHub.cursorCreateAgent(userId,
          await readJson(req, 8192)));
      }
      const cursorAgentRoute = path.match(/^\/api\/account\/cursor\/agents\/([A-Za-z0-9_-]{8,120})$/);
      if (req.method === "GET" && cursorAgentRoute) {
        return send(res, 200, await accountHub.cursorAgent(userId, cursorAgentRoute[1]));
      }
      const cursorArtifacts = path.match(/^\/api\/account\/cursor\/agents\/([A-Za-z0-9_-]{8,120})\/artifacts$/);
      if (cursorArtifacts && req.method === "GET") {
        return send(res, 200, await accountHub.cursorArtifacts(userId,
          cursorArtifacts[1]));
      }
      const cursorArtifactLink = path.match(/^\/api\/account\/cursor\/agents\/([A-Za-z0-9_-]{8,120})\/artifacts\/download$/);
      if (cursorArtifactLink && req.method === "GET") {
        return send(res, 200, await accountHub.cursorArtifactLink(userId,
          cursorArtifactLink[1], url.searchParams.get("path")));
      }
      const cursorRunsRoute = path.match(/^\/api\/account\/cursor\/agents\/([A-Za-z0-9_-]{8,120})\/runs$/);
      if (cursorRunsRoute && req.method === "GET") {
        return send(res, 200, await accountHub.cursorRuns(userId, cursorRunsRoute[1]));
      }
      if (cursorRunsRoute && req.method === "POST") {
        return send(res, 201, await accountHub.cursorFollowUp(userId,
          cursorRunsRoute[1], await readJson(req, 8192)));
      }
      const cursorRunRoute = path.match(/^\/api\/account\/cursor\/agents\/([A-Za-z0-9_-]{8,120})\/runs\/([A-Za-z0-9_-]{8,120})$/);
      if (cursorRunRoute && req.method === "GET") {
        return send(res, 200, await accountHub.cursorRun(userId,
          cursorRunRoute[1], cursorRunRoute[2]));
      }
      const cursorStreamRoute = path.match(/^\/api\/account\/cursor\/agents\/([A-Za-z0-9_-]{8,120})\/runs\/([A-Za-z0-9_-]{8,120})\/stream$/);
      if (cursorStreamRoute && req.method === "GET") {
        // Verify this mobile account owns a key before starting the response.
        accountHub.cursorKey(userId);
        const controller = new AbortController();
        const disconnect = () => controller.abort();
        res.on("close", disconnect);
        res.writeHead(200, {
          "content-type": "text/event-stream; charset=utf-8",
          "cache-control": "no-cache, no-transform",
          "connection": "keep-alive",
          "x-content-type-options": "nosniff",
          "x-accel-buffering": "no",
        });
        res.write(": oagent-cursor-live\n\n");
        try {
          for await (const event of accountHub.cursorEvents(userId,
            cursorStreamRoute[1], cursorStreamRoute[2], {
              signal: controller.signal,
              lastEventId: req.headers["last-event-id"] || null,
            })) {
            if (controller.signal.aborted) break;
            // No model reasoning, raw tool arguments or provider secrets.
            res.write("event: " + event.event + "\n" +
              (event.id ? "id: " + event.id + "\n" : "") +
              "data: " + JSON.stringify(event.data) + "\n\n");
          }
        } catch (error) {
          if (!controller.signal.aborted && !res.destroyed) {
            res.write("event: error\ndata: " + JSON.stringify({
              message: error.status === 410
                ? "Stream expired. Open the final run result."
                : "Cursor live stream ended. Refresh the run status.",
            }) + "\n\n");
          }
        } finally {
          res.off("close", disconnect);
          controller.abort();
          if (!res.writableEnded && !res.destroyed) res.end();
        }
        return;
      }
      const cursorCancelRoute = path.match(/^\/api\/account\/cursor\/agents\/([A-Za-z0-9_-]{8,120})\/runs\/([A-Za-z0-9_-]{8,120})\/cancel$/);
      if (cursorCancelRoute && req.method === "POST") {
        return send(res, 200, await accountHub.cursorCancel(userId,
          cursorCancelRoute[1], cursorCancelRoute[2]));
      }
      if (req.method === "GET" && path === "/api/account/github") {
        return send(res, 200, accountHub.githubStatus(userId));
      }
      if (req.method === "PUT" && path === "/api/account/github") {
        return send(res, 200, await accountHub.connectGithub(userId, await readJson(req, 4096)));
      }
      if (req.method === "DELETE" && path === "/api/account/github") {
        return send(res, 200, accountHub.disconnectGithub(userId));
      }
      if (req.method === "GET" && path === "/api/account/github/repos") {
        return send(res, 200, { repos: await accountHub.githubRepos(userId) });
      }
      if (req.method === "GET" && path === "/api/account/attachments") {
        return send(res, 200, { attachments: accountHub.attachments(userId) });
      }
      if (req.method === "POST" && path === "/api/account/attachments") {
        return send(res, 201, accountHub.saveAttachment(userId, await readJson(req, 2200000)));
      }
      const attachment = path.match(/^\/api\/account\/attachments\/([0-9a-f-]+)$/);
      if (req.method === "DELETE" && attachment) {
        return send(res, 200, accountHub.deleteAttachment(userId, attachment[1]));
      }
      if (req.method === "GET" && path === "/api/account/threads") {
        return send(res, 200, { threads: accountHub.threads(userId) });
      }
      const userThread = path.match(/^\/api\/account\/threads\/([0-9a-f-]+)$/);
      if (req.method === "GET" && userThread) {
        return send(res, 200, accountHub.thread(userId, userThread[1]));
      }
      if (req.method === "POST" && path === "/api/account/chat") {
        return send(res, 200, await accountHub.send(userId, await readJson(req, 8192)));
      }
      throw new DomainError(404, "Account API endpoint not found");
    }
    if (!owner && !worker) {
      // Member tokens never unlock legacy project, worker, task, event or
      // admin endpoints. A minimal snapshot lets an invited mobile user
      // connect without seeing the owner's machines, files or approvals.
      if (req.method === "GET" && path === "/api/state") {
        return send(res, 200, { workers: [], tasks: [], nextSequence: 1 });
      }
      if (req.method === "GET" && path === "/api/events") {
        return send(res, 200, { events: [], nextSequence: 1 });
      }
      throw new DomainError(403, "This account is not authorized to operate the owner's workspace");
    }

    // A member's private AI token never unlocks owner remote-agent activity.
    if (req.method === "GET" && path === "/api/remote/overview") {
      return send(res, 200, projectHub.remoteOverview());
    }

    // Unified, capability-aware project registry: no simulated external work.
    if (req.method === "GET" && path === "/api/projects") {
      return send(res, 200, await projectHub.list());
    }
    if (req.method === "POST" && path === "/api/providers/codex/local/history") {
      return send(res, 201, projectHub.requestLocalCodexHistory(await readJson(req), req.headers["idempotency-key"]));
    }
    if (req.method === "POST" && path === "/api/providers/codex/local/turns/confirm") {
      return send(res, 201, projectHub.confirmLocalCodexTurn(await readJson(req), req.headers["idempotency-key"]));
    }
    if (req.method === "POST" && path === "/api/providers/codex/local/turns") {
      return send(res, 201, projectHub.requestLocalCodexTurn(await readJson(req), req.headers["idempotency-key"]));
    }
    if (req.method === "POST" && path === "/api/providers/codex/tasks") {
      return send(res, 201, projectHub.requestCodexTask(await readJson(req), req.headers["idempotency-key"]));
    }
    if (req.method === "GET" && path === "/api/integrations") {
      return send(res, 200, { sources: projectHub.sources() });
    }
    if (req.method === "POST" && path === "/api/projects") {
      return send(res, 201, projectHub.create(await readJson(req)));
    }
    const projectRoute = path.match(/^\/api\/projects\/([^/]+)$/);
    if (req.method === "GET" && projectRoute) {
      return send(res, 200, await projectHub.details(decodeURIComponent(projectRoute[1])));
    }
    const projectMessage = path.match(/^\/api\/projects\/([^/]+)\/messages$/);
    if (req.method === "POST" && projectMessage) {
      return send(res, 200, await projectHub.send(decodeURIComponent(projectMessage[1]), await readJson(req)));
    }

    if (req.method === "POST" && path === "/api/ai/refine") {
      return send(res, 200, await agentRuntime.refinePrompt(await readJson(req)));
    }
    if (req.method === "GET" && path === "/api/ai/status") return send(res, 200, agentRuntime.status());
    if (req.method === "GET" && path === "/api/ai/threads") return send(res, 200, { threads: agentRuntime.threads() });
    const threadPath = path.match(/^\/api\/ai\/threads\/([0-9a-f-]+)$/);
    if (req.method === "GET" && threadPath) return send(res, 200, agentRuntime.getThread(threadPath[1]));
    if (req.method === "POST" && path === "/api/ai/chat") {
      const body = await readJson(req);
      const result = await agentRuntime.send(body);
      return send(res, 200, result);
    }

    // Manual desktop input is separate from screen capture. The Windows
    // helper must be launched visibly, supply its worker token, and display
    // a short-lived code entered by the owner on the phone. Never persist input.
    if (path.startsWith("/api/input/")) {
      if (!owner) throw new DomainError(403, "Only the workspace owner may control the screen");
      if (req.method === "GET" && path === "/api/input/status")
        return send(res, 200, remoteInput.status());
      if (req.method === "POST" && path === "/api/input/pair")
        return send(res, 200, remoteInput.pair(await readJson(req, 256)));
      if (req.method === "POST" && path === "/api/input/action")
        return send(res, 200, remoteInput.action(await readJson(req, 2048)));
      if (req.method === "POST" && path === "/api/input/stop")
        return send(res, 200, remoteInput.stop());
      throw new DomainError(404, "Unknown remote input endpoint");
    }
    if (path.startsWith("/api/workers/remote-input/")) {
      const body = await readJson(req, 256);
      const id = body.workerId;
      const known = core.snapshot().workers.some(w => w.id === id && w.status === "online");
      if (!known) throw new DomainError(409, "Enrolled Windows worker is not online");
      if (req.method === "POST" && path === "/api/workers/remote-input/prepare")
        return send(res, 200, remoteInput.prepare(id));
      if (req.method === "POST" && path === "/api/workers/remote-input/next")
        return send(res, 200, remoteInput.next(id));
      if (req.method === "POST" && path === "/api/workers/remote-input/stop")
        return send(res, 200, remoteInput.stop(id));
      throw new DomainError(404, "Unknown Windows input-helper endpoint");
    }
    // Explicit owner-only file access. The relay is in memory, expiring after
    // 90 seconds; file text must never enter persistent tasks/events/logs.
    if (path === "/api/vscode/files/request" && req.method === "POST") {
      if (!owner) throw new DomainError(403, "Only the workspace owner may browse or edit VS Code files");
      const value = await readJson(req, 60000);
      const enrolled = core.snapshot().workers.some(w =>
        w.id === value.workerId && w.status === "online" &&
        w.capabilities?.includes("vscode_workspace_files"));
      if (!enrolled) throw new DomainError(409, "No enrolled VS Code file companion online");
      return send(res, 201, vscodeFileRelay.request(value));
    }
    const fileResult = path.match(/^\/api\/vscode\/files\/([0-9a-f-]{36})$/);
    if (req.method === "GET" && fileResult) {
      if (!owner) throw new DomainError(403,"Owner-only file result");
      return send(res, 200, vscodeFileRelay.status(fileResult[1]));
    }
    if (req.method === "GET" && path === "/api/vscode/workspaces") {
      if (!owner) throw new DomainError(403, "Owner-only editor workspace feed");
      return send(res, 200, vscodePresence.list());
    }
    if (req.method === "GET" && path === "/api/state") return send(res, 200, core.snapshot());
    if (req.method === "GET" && path === "/api/events") {
      const after = Number(url.searchParams.get("after") ?? 0);
      if (!Number.isSafeInteger(after) || after < 0) throw new DomainError(400, "Invalid event cursor");
      return send(res, 200, { events: core.events(after), nextSequence: core.data.sequence + 1 });
    }
    if (req.method === "GET" && path === "/api/stream") {
      res.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-cache", "connection": "keep-alive", "x-content-type-options": "nosniff" });
      res.write(": connected\n\n");
      const unsubscribe = core.subscribe(event => res.write(`data: ${JSON.stringify(event)}\n\n`));
      const heartbeat = setInterval(() => res.write(": keepalive\n\n"), 20000);
      req.on("close", () => { unsubscribe(); clearInterval(heartbeat); });
      return;
    }
    if (req.method === "POST" && path === "/api/tasks") {
      const value = core.createTask(await readJson(req), req.headers["idempotency-key"]);
      return send(res, 201, value);
    }
    const codexDecision = path.match(/^\/api\/tasks\/([0-9a-f-]+)\/approvals\/([a-zA-Z0-9_-]+)\/decision$/);
    if (req.method === "POST" && codexDecision) {
      const body = await readJson(req);
      return send(res, 200, core.decideCodexApproval(codexDecision[1], codexDecision[2], body.approve));
    }
    const taskDetail = path.match(/^\/api\/tasks\/([0-9a-f-]+)$/);
    if (req.method === "GET" && taskDetail) return send(res, 200, core.getTask(taskDetail[1]));
    const decision = path.match(/^\/api\/tasks\/([0-9a-f-]+)\/decision$/);
    if (req.method === "POST" && decision) {
      const value = await readJson(req);
      if (typeof value.approve !== "boolean") throw new DomainError(400, "approve must be boolean");
      return send(res, 200, core.decide(decision[1], value.approve));
    }
    const cancel = path.match(/^\/api\/tasks\/([0-9a-f-]+)\/cancel$/);
    if (req.method === "POST" && cancel) return send(res, 200, core.cancel(cancel[1]));

    const codexLocalSync = path.match(/^\/api\/workers\/([a-zA-Z0-9_-]+)\/codex\/local\/sync$/);
    if (req.method === "POST" && codexLocalSync) {
      return send(res, 200, projectHub.publishCodexLocal(codexLocalSync[1], await readJson(req, 131072)));
    }
    const codexSync = path.match(/^\/api\/workers\/([a-zA-Z0-9_-]+)\/codex\/sync$/);
    if (req.method === "POST" && codexSync) {
      return send(res, 200, projectHub.publishCodex(codexSync[1], await readJson(req)));
    }

    if (req.method === "POST" && path === "/api/workers/register") {
      return send(res, 201, core.registerWorker(await readJson(req)));
    }
    const vscodeFilePath = path.match(/^\/api\/workers\/([a-zA-Z0-9_-]+)\/vscode\/files\/(next|finish|stop)$/);
    if (vscodeFilePath) {
      const wid = vscodeFilePath[1], operation = vscodeFilePath[2];
      const known = core.data.workers[wid];
      if (!known?.capabilities?.includes("vscode_workspace_files"))
        throw new DomainError(403, "Worker not enrolled for explicit VS Code file access");
      if (req.method !== "POST") throw new DomainError(405, "POST required");
      if (operation === "next") return send(res, 200, vscodeFileRelay.claim(wid));
      if (operation === "finish") return send(res, 200,
        vscodeFileRelay.finish(wid, await readJson(req, 100000)));
      if (operation === "stop") { vscodeFileRelay.clearWorker(wid);return send(res,200,{ok:true}); }
    }
    const vscodeSnapshot = path.match(/^\/api\/workers\/([a-zA-Z0-9_-]+)\/vscode\/snapshot$/);
    if (vscodeSnapshot && req.method === "POST") {
      const worker = core.data.workers[vscodeSnapshot[1]];
      if (!worker?.capabilities?.includes("vscode_open_file"))
        throw new DomainError(403, "An enrolled VS Code companion is required");
      return send(res, 200, vscodePresence.publish(vscodeSnapshot[1], await readJson(req, 36000)));
    }
    if (vscodeSnapshot && req.method === "DELETE") {
      return send(res, 200, vscodePresence.clear(vscodeSnapshot[1]));
    }
    const heartbeat = path.match(/^\/api\/workers\/([a-zA-Z0-9_-]+)\/heartbeat$/);
    if (req.method === "POST" && heartbeat) return send(res, 200, core.heartbeat(heartbeat[1]));
    const next = path.match(/^\/api\/workers\/([a-zA-Z0-9_-]+)\/next$/);
    if (req.method === "POST" && next) return send(res, 200, { task: core.claim(next[1]) });
    const codexUpdate = path.match(/^\/api\/workers\/([a-zA-Z0-9_-]+)\/tasks\/([0-9a-f-]+)\/update$/);
    if (req.method === "POST" && codexUpdate) {
      return send(res, 200, core.appendTaskUpdate(codexUpdate[1], codexUpdate[2], await readJson(req)));
    }
    const codexPermission = path.match(/^\/api\/workers\/([a-zA-Z0-9_-]+)\/tasks\/([0-9a-f-]+)\/approvals$/);
    if (req.method === "POST" && codexPermission) {
      return send(res, 201, core.requestCodexApproval(codexPermission[1], codexPermission[2], await readJson(req)));
    }
    const codexPermissionStatus = path.match(/^\/api\/workers\/([a-zA-Z0-9_-]+)\/tasks\/([0-9a-f-]+)\/approvals\/([a-zA-Z0-9_-]+)$/);
    if (req.method === "GET" && codexPermissionStatus) {
      return send(res, 200, core.codexApprovalStatus(codexPermissionStatus[1], codexPermissionStatus[2], codexPermissionStatus[3]));
    }
    const finish = path.match(/^\/api\/workers\/([a-zA-Z0-9_-]+)\/tasks\/([0-9a-f-]+)\/finish$/);
    if (req.method === "POST" && finish) return send(res, 200, core.finish(finish[1], finish[2], await readJson(req)));
    throw new DomainError(404, "Endpoint not found");
  } catch (err) {
    if (!res.headersSent && !res.destroyed) send(res, err.status || 500, { error: err.status ? err.message : "Internal server error" });
    if (!err.status) console.error(err);
  }
});
server.listen(port, host, () => console.log(`O-AGENT control plane listening on http://${host}:${port}`));
