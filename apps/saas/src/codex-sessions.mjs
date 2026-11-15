import {isAbsolute,relative,resolve,sep} from "node:path";
import {httpError,isUUID} from "./operations.mjs";

const SESSION=/^[A-Za-z0-9_-]{8,120}$/;
const clean=(value,max)=>typeof value==="string"&&value.length<=max&&
  !/[\x00-\x08\x0b\x0c\x0e-\x1f]/.test(value);
export function withinRoot(root,folder) {
  if(typeof root!=="string"||typeof folder!=="string"||
     !isAbsolute(root)||!isAbsolute(folder))return false;
  const r=resolve(root),f=resolve(folder);
  const diff=relative(r,f);
  return diff!==".."&&!diff.startsWith(".."+sep)&&!isAbsolute(diff);
}
export function validateCodexSessions(body,workspaceRoot) {
  if(!body||!Array.isArray(body.sessions)||body.sessions.length>10||
    !withinRoot(workspaceRoot,workspaceRoot))
    throw httpError(400,"Invalid Codex session snapshot");
  const found=new Set(),accepted=[];
  for(const row of body.sessions){
    if(!row||typeof row!=="object"||
      !SESSION.test(row.sessionId)||found.has(row.sessionId)||
      !clean(row.cwd,600)||!withinRoot(workspaceRoot,row.cwd)||
      !clean(row.title,100)||!row.title||!clean(row.preview,240)||
      !["cli","vscode","unknown"].includes(row.sourceKind)||
      !Array.isArray(row.messages)||row.messages.length>20)
      throw httpError(400,"Invalid verified Codex session");
    const when=new Date(row.updatedAt);
    if(!Number.isFinite(when.getTime())||
      when.getTime()>Date.now()+86400000)
      throw httpError(400,"Invalid stored session time");
    const messages=[];
    for(const m of row.messages){
      if(!m||!["user","assistant"].includes(m.role)||
        !clean(m.text,1400)||!m.text)
        throw httpError(400,"Invalid stored session messages");
      messages.push({role:m.role,text:m.text});
    }
    found.add(row.sessionId);
    accepted.push({...row,updatedAt:when.toISOString(),messages});
  }
  return accepted;
}
export async function storeCodexSessions(client,tenantId,deviceId,body) {
  if(!isUUID(deviceId))throw httpError(400,"Invalid device ID");
  const {rows:devices}=await client.query(
    "SELECT workspace_root,revoked_at FROM devices WHERE id=$1 FOR UPDATE",
    [deviceId]);
  if(!devices[0]||devices[0].revoked_at||
    !devices[0].workspace_root)throw httpError(403,"Enrolled worker unavailable");
  const records=validateCodexSessions(body,devices[0].workspace_root);
  for(const item of records){
    await client.query(
      "INSERT INTO codex_sessions(tenant_id,device_id,session_id,cwd,title,preview,source_kind,updated_at,synced_at,messages) "+
      "VALUES($1,$2,$3,$4,$5,$6,$7,$8,now(),$9::jsonb) "+
      "ON CONFLICT(tenant_id,device_id,session_id) DO UPDATE SET "+
      "cwd=EXCLUDED.cwd,title=EXCLUDED.title,preview=EXCLUDED.preview,"+
      "source_kind=EXCLUDED.source_kind,updated_at=EXCLUDED.updated_at,"+
      "synced_at=now(),messages=EXCLUDED.messages",
      [tenantId,deviceId,item.sessionId,item.cwd,item.title,
        item.preview,item.sourceKind,item.updatedAt,JSON.stringify(item.messages)]);
  }
  // Only replace this worker's sessions after the complete snapshot passed
  // validation. Other tenants and other enrolled computers are untouched.
  await client.query(
    "DELETE FROM codex_sessions WHERE device_id=$1 AND "+
    "NOT(session_id=ANY($2::text[]))",
    [deviceId,records.map(x=>x.sessionId)]);
  return {synced:records.length};
}
export async function listCodexSessions(client) {
  const {rows}=await client.query(
    "SELECT s.session_id AS \"sessionId\",s.device_id AS \"deviceId\","+
    "d.name AS \"deviceName\",s.cwd,s.title,s.preview,"+
    "s.source_kind AS \"sourceKind\",s.updated_at AS \"updatedAt\","+
    "s.synced_at AS \"syncedAt\",s.messages "+
    "FROM codex_sessions s JOIN devices d ON d.id=s.device_id "+
    "WHERE d.revoked_at IS NULL ORDER BY s.updated_at DESC LIMIT 80");
  return rows;
}
