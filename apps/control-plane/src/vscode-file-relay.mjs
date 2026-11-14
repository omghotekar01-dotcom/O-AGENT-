import { randomUUID } from "node:crypto";
import { DomainError } from "./core.mjs";

// Never persisted: the private backend only relays an owner's individual
// file request to a visibly enrolled VS Code window, and expires all text.
const TTL_MS = 90_000;
const MAX_REQUESTS = 12;
const MAX_FILE_CHARS = 48_000;
const MAX_RESPONSE_BYTES = 90_000;
const OPERATIONS = new Set(["list","read","write","create","rename","delete"]);
function validPath(path, allowRoot = false) {
  return typeof path === "string" && path.length <= 350 &&
    (allowRoot || path.length > 0) && !/[\u0000-\u001f]/.test(path) &&
    !path.startsWith("/") && !/^[A-Za-z]:/.test(path) &&
    (!path || path.split(/[\\/]/).every(x => x && x !== "." && x !== ".."));
}
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
    if (!OPERATIONS.has(op))
      throw new DomainError(400, "Unsupported VS Code operation");
    const path = value.path ?? "";
    if (!validPath(path, op === "list"))
      throw new DomainError(400, "Invalid workspace-relative path");
    if (op === "rename" && !validPath(value.newPath))
      throw new DomainError(400, "Invalid new workspace-relative file path");
    if (["write","rename","delete"].includes(op) &&
        (typeof value.expectedHash !== "string" || !/^[a-f0-9]{64}$/.test(value.expectedHash)))
      throw new DomainError(400, "Original file hash required to prevent overwriting a changed file");
    if (["write","create"].includes(op) &&
        (typeof value.content !== "string" || value.content.length > MAX_FILE_CHARS ||
         value.content.includes("\0")))
      throw new DomainError(400, "Only text files up to 48,000 characters may be edited");
    if (op === "rename" && path === value.newPath)
      throw new DomainError(400, "Choose a different file name");
    if ([...this.requests.values()].filter(r => r.workerId === workerId).length >= MAX_REQUESTS)
      throw new DomainError(429, "Too many pending workspace file requests");
    const id = randomUUID();
    const request = {
      id, workerId, op, path, state: "queued", at: this.now(),
      // The original file hash is bound to the single edited version.
      ...(op === "write" || op === "create" ? {content:value.content} : {}),
      ...(["write","rename","delete"].includes(op) ? {expectedHash:value.expectedHash} : {}),
      ...(op === "rename" ? {newPath:value.newPath} : {}),
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
      ...(request.op === "write" || request.op === "create" ? {content:request.content} : {}),
      ...(["write","rename","delete"].includes(request.op) ?
        {expectedHash:request.expectedHash} : {}),
      ...(request.op === "rename" ? {newPath:request.newPath} : {}),
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
    delete r.newPath;
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
