import { randomUUID } from "node:crypto";
import { DomainError } from "./core.mjs";

// Never persisted: the private backend only relays an owner's individual
// file request to a visibly enrolled VS Code window, and expires all text.
const TTL_MS = 90_000;
const MAX_REQUESTS = 12;
const MAX_FILE_CHARS = 48_000;
const MAX_RESPONSE_BYTES = 90_000;
const WORKER_IDLE_MS = 30_000;

export class VscodeFileRelay {
  constructor({ now = () => Date.now() } = {}) {
    this.now = now;
    this.requests = new Map();
    this.workers = new Map();
  }
  online(workerId) {
    return this.now() - (this.workers.get(workerId) ?? 0) < WORKER_IDLE_MS;
  }
  heartbeat(workerId) {
    this.workers.set(workerId, this.now());
  }
  prune() {
    for (const [id, r] of this.requests)
      if (this.now() - r.at > TTL_MS) this.requests.delete(id);
    for (const [id, at] of this.workers)
      if (this.now() - at > WORKER_IDLE_MS) this.workers.delete(id);
  }
  request(value) {
    this.prune();
    if (!value || typeof value !== "object" || Array.isArray(value))
      throw new DomainError(400, "Invalid workspace request");
    const { workerId, op } = value;
    if (typeof workerId !== "string" || !/^[A-Za-z0-9_-]{1,100}$/.test(workerId) ||
        !this.online(workerId))
      throw new DomainError(409, "VS Code workspace companion is not online. Reopen the trusted folder and start it.");
    if (!["list", "read", "write"].includes(op))
      throw new DomainError(400, "Unsupported VS Code operation");
    const path = value.path ?? "";
    if (typeof path !== "string" || path.length > 350 ||
        /[\u0000-\u001f]/.test(path) ||
        (path && (path.startsWith("/") || /^[A-Za-z]:/.test(path) ||
          path.split(/[\\/]/).some(x => !x || x === "." || x === ".."))))
      throw new DomainError(400, "Invalid workspace-relative path");
    if (op !== "list" && !path)
      throw new DomainError(400, "Choose an existing file");
    if (op === "write" && (typeof value.content !== "string" ||
        value.content.length > MAX_FILE_CHARS ||
        typeof value.expectedHash !== "string" ||
        !/^[a-f0-9]{64}$/.test(value.expectedHash)))
      throw new DomainError(400, "Edited text or expected file version is invalid");
    if ([...this.requests.values()].filter(r => r.workerId === workerId).length >= MAX_REQUESTS)
      throw new DomainError(429, "Too many pending workspace file requests");
    const id = randomUUID();
    const request = {
      id, workerId, op, path, state: "queued", at: this.now(),
      // The original file hash is bound to the single edited version.
      ...(op === "write" ? {content:value.content,expectedHash:value.expectedHash} : {}),
    };
    this.requests.set(id, request);
    return {id, state:request.state, op, path};
  }
  claim(workerId) {
    this.prune();
    this.heartbeat(workerId);
    const request = [...this.requests.values()].find(r => r.workerId === workerId && r.state === "queued");
    if (!request) return {request:null};
    request.state = "running";
    return {request:{
      id:request.id,op:request.op,path:request.path,
      ...(request.op === "write" ? {content:request.content,expectedHash:request.expectedHash} : {}),
    }};
  }
  finish(workerId,value) {
    this.prune();
    const r = this.requests.get(value?.id);
    if (!r || r.workerId !== workerId || r.state !== "running")
      throw new DomainError(409,"Workspace request expired or belongs to another editor");
    if (value.ok !== true && value.ok !== false)
      throw new DomainError(400,"Missing result status");
    let result=null,error=null;
    if (value.ok) {
      const body = JSON.stringify(value.result ?? {});
      if (Buffer.byteLength(body,"utf8") > MAX_RESPONSE_BYTES)
        throw new DomainError(413,"File response too large");
      result=JSON.parse(body);
    } else {
      error=String(value.error ?? "Workspace operation failed").slice(0,300);
    }
    r.state=value.ok?"completed":"failed";
    r.result=result; r.error=error;
    delete r.content;
    delete r.expectedHash;
    return {ok:true};
  }
  status(id) {
    this.prune();
    const r=this.requests.get(id);
    if (!r) throw new DomainError(404, "Workspace result expired. Request it again.");
    return { id:r.id,op:r.op,path:r.path,state:r.state,
      ...(r.state === "completed" ? { result:r.result } : {}),
      ...(r.state === "failed" ? { error:r.error } : {}) };
  }
  clearWorker(workerId) {
    this.workers.delete(workerId);
    for (const [id,r] of this.requests) if(r.workerId===workerId)this.requests.delete(id);
  }
}
