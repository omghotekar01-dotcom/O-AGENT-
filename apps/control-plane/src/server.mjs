import { createServer } from "node:http";
import { readFileSync, writeFileSync, renameSync, mkdirSync, existsSync } from "node:fs";
import { resolve, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { timingSafeEqual } from "node:crypto";
import { ControlPlane, DomainError } from "./core.mjs";
import { AgentRuntime } from "./agent-runtime.mjs";

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
function readJson(req) {
  return new Promise((resolveBody, reject) => {
    let body = "";
    req.on("data", chunk => {
      body += chunk;
      if (body.length > 32768) {
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
    if (req.method === "GET" && path === "/dashboard.css") return staticFile(res, "dashboard.css", "text/css; charset=utf-8");
    if (req.method === "GET" && path === "/dashboard.js") return staticFile(res, "dashboard.js", "text/javascript; charset=utf-8");
    const isWorkerRoute = path.startsWith("/api/workers/");
    if (!authorized(req, isWorkerRoute ? workerToken : apiToken)) throw new DomainError(401, "Invalid authorization token");

    if (req.method === "GET" && path === "/api/ai/status") return send(res, 200, agentRuntime.status());
    if (req.method === "GET" && path === "/api/ai/threads") return send(res, 200, { threads: agentRuntime.threads() });
    const threadPath = path.match(/^\/api\/ai\/threads\/([0-9a-f-]+)$/);
    if (req.method === "GET" && threadPath) return send(res, 200, agentRuntime.getThread(threadPath[1]));
    if (req.method === "POST" && path === "/api/ai/chat") {
      const body = await readJson(req);
      const result = await agentRuntime.send(body);
      return send(res, 200, result);
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
    const decision = path.match(/^\/api\/tasks\/([0-9a-f-]+)\/decision$/);
    if (req.method === "POST" && decision) {
      const value = await readJson(req);
      if (typeof value.approve !== "boolean") throw new DomainError(400, "approve must be boolean");
      return send(res, 200, core.decide(decision[1], value.approve));
    }
    const cancel = path.match(/^\/api\/tasks\/([0-9a-f-]+)\/cancel$/);
    if (req.method === "POST" && cancel) return send(res, 200, core.cancel(cancel[1]));

    if (req.method === "POST" && path === "/api/workers/register") {
      return send(res, 201, core.registerWorker(await readJson(req)));
    }
    const heartbeat = path.match(/^\/api\/workers\/([a-zA-Z0-9_-]+)\/heartbeat$/);
    if (req.method === "POST" && heartbeat) return send(res, 200, core.heartbeat(heartbeat[1]));
    const next = path.match(/^\/api\/workers\/([a-zA-Z0-9_-]+)\/next$/);
    if (req.method === "POST" && next) return send(res, 200, { task: core.claim(next[1]) });
    const finish = path.match(/^\/api\/workers\/([a-zA-Z0-9_-]+)\/tasks\/([0-9a-f-]+)\/finish$/);
    if (req.method === "POST" && finish) return send(res, 200, core.finish(finish[1], finish[2], await readJson(req)));
    throw new DomainError(404, "Endpoint not found");
  } catch (err) {
    if (!res.headersSent && !res.destroyed) send(res, err.status || 500, { error: err.status ? err.message : "Internal server error" });
    if (!err.status) console.error(err);
  }
});
server.listen(port, host, () => console.log(`O-AGENT control plane listening on http://${host}:${port}`));
