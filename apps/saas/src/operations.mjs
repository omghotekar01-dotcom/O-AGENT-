import {randomBytes,randomUUID} from "node:crypto";
import {audit} from "./store.mjs";
import {hexSha256,sha256,parseEd25519PublicKey} from "./device-crypto.mjs";

export const httpError=(status,message)=>Object.assign(Error(message),{status});
const ID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const RUN_KINDS=new Set(["workspace_inventory","claude_agent_turn",
  "copilot_sdk_turn","codex_cli_turn"]);
const MODES=new Set(["read_only","workspace_write"]);
export const isUUID=s=>typeof s==="string"&&ID.test(s);
export function actionDigest({deviceId,kind,mode,prompt,cwd,sessionId=null}) {
  return hexSha256(JSON.stringify({deviceId,kind,mode,prompt,cwd,sessionId}));
}
function text(value,max,name) {
  if(typeof value!=="string"||!value.trim()||value.length>max||
     /[\x00-\x1f\x7f]/.test(value.replace(/\n/g,"")))
    throw httpError(400,"Invalid "+name);
  return value.trim();
}
export async function startEnrollment(pool,body,sourceHash) {
  const name=text(body?.name,80,"device name");
  const key=parseEd25519PublicKey(body?.publicKeyPem);
  const client=await pool.connect();
  try{
    await client.query("BEGIN");
    await client.query("DELETE FROM pending_devices WHERE expires_at<now()");
    const requests=await client.query(
      "SELECT count(*)::int AS count FROM pending_devices WHERE source_hash=$1 AND created_at>now()-interval '1 hour'",[sourceHash]);
    if(requests.rows[0].count>=8)
      throw httpError(429,"Too many pairing attempts. Try again later.");
    const token="oen_"+randomBytes(32).toString("base64url");
    const id=randomUUID();
    await client.query(
      "INSERT INTO pending_devices(id,name,public_key,token_hash,source_hash,expires_at) VALUES($1,$2,$3,$4,$5,now()+interval '10 minutes')",
      [id,name,key,sha256(token),sourceHash]);
    await client.query("COMMIT");
    return {pairingToken:token,expiresInSeconds:600};
  }catch(err){await client.query("ROLLBACK");throw err;}
  finally{client.release();}
}
export async function approveEnrollment(client,tenantId,subject,token) {
  if(typeof token!=="string"||!/^oen_[A-Za-z0-9_-]{43}$/.test(token))
    throw httpError(400,"Invalid or expired enrollment request");
  const pending=await client.query(
    "SELECT id,name,public_key FROM pending_devices WHERE token_hash=$1 AND expires_at>now() FOR UPDATE",
    [sha256(token)]);
  if(!pending.rows[0])throw httpError(404,"Pairing request expired or already used");
  const deviceId=randomUUID(), p=pending.rows[0];
  await client.query(
    "INSERT INTO devices(id,tenant_id,name) VALUES($1,$2,$3)",[deviceId,tenantId,p.name]);
  await client.query(
    "INSERT INTO device_auth_keys(device_id,tenant_id,public_key) VALUES($1,$2,$3)",
    [deviceId,tenantId,p.public_key]);
  await client.query("DELETE FROM pending_devices WHERE id=$1",[p.id]);
  await audit(client,tenantId,subject,"device.enrolled",deviceId);
  return {deviceId,name:p.name};
}
export async function listDevices(client) {
  const result=await client.query(
    "SELECT id,name,capabilities,last_seen_at,created_at,revoked_at FROM devices ORDER BY created_at DESC LIMIT 100");
  return result.rows;
}
export async function revokeDevice(client,tenantId,subject,id) {
  if(!isUUID(id))throw httpError(400,"Invalid device");
  const deleted=await client.query(
    "UPDATE devices SET revoked_at=now(),capabilities='[]'::jsonb WHERE id=$1 AND revoked_at IS NULL RETURNING id",[id]);
  if(!deleted.rowCount)throw httpError(404,"Device not found");
  await client.query("UPDATE device_auth_keys SET revoked_at=now() WHERE device_id=$1 AND tenant_id=$2",
    [id,tenantId]);
  await audit(client,tenantId,subject,"device.revoked",id);
  return {revoked:true};
}
export async function updateCapabilities(client,tenantId,deviceId,requested) {
  if(!Array.isArray(requested)||requested.length>8||
      requested.some(x=>!RUN_KINDS.has(x)))
    throw httpError(400,"Invalid supported capabilities");
  const capabilities=[...new Set(requested)];
  const result=await client.query(
    "UPDATE devices SET capabilities=$1::jsonb,last_seen_at=now() WHERE id=$2 AND revoked_at IS NULL RETURNING id",
    [JSON.stringify(capabilities),deviceId]);
  if(!result.rowCount)throw httpError(403,"Device revoked");
  await audit(client,tenantId,deviceId,"device.capabilities",deviceId,{capabilities});
  return {capabilities};
}
export async function heartbeat(client,deviceId) {
  const result=await client.query(
    "UPDATE devices SET last_seen_at=now() WHERE id=$1 AND revoked_at IS NULL RETURNING id",[deviceId]);
  if(!result.rowCount)throw httpError(403,"Device revoked");
  return {ok:true};
}
export async function createRun(client,tenantId,subject,body,requestKey) {
  if(!isUUID(body?.deviceId)||!RUN_KINDS.has(body?.kind)||
      !MODES.has(body?.mode)||typeof requestKey!=="string"||
      !/^[A-Za-z0-9_-]{16,128}$/.test(requestKey))
    throw httpError(400,"Invalid run request");
  const kind=body.kind, mode=body.mode;
  const prompt=kind==="workspace_inventory"?"Inspect enrolled workspace files":
    text(body.prompt,4000,"prompt");
  const cwd=kind==="workspace_inventory"?"":text(body.cwd,600,"workspace path");
  if(cwd && !/^(?:[A-Za-z]:[\\/]|\/)/.test(cwd))
    throw httpError(400,"Workspace must be an absolute enrolled directory");
  const sessionId=body.sessionId??null;
  if(sessionId!=null && (typeof sessionId!=="string" ||
      !/^[A-Za-z0-9_-]{8,120}$/.test(sessionId)))
    throw httpError(400,"Invalid native provider session ID");
  if(kind==="codex_cli_turn" && sessionId===null)
    throw httpError(400,"Codex CLI requires a verified saved session ID");
  const device=await client.query(
    "SELECT capabilities FROM devices WHERE id=$1 AND revoked_at IS NULL AND last_seen_at>now()-interval '2 minutes'",
    [body.deviceId]);
  const caps=device.rows[0]?.capabilities;
  if(!Array.isArray(caps)||!caps.includes(kind))
    throw httpError(409,"The enrolled device is offline or does not support this provider");
  const digest=actionDigest({deviceId:body.deviceId,kind,mode,prompt,cwd,sessionId});
  const prior=await client.query("SELECT id,action_hash,status FROM runs WHERE request_key=$1",
    [requestKey]);
  if(prior.rows[0]) {
    if(prior.rows[0].action_hash!==digest)throw httpError(409,"Idempotency key reused for another run");
    return {runId:prior.rows[0].id,status:prior.rows[0].status,reused:true};
  }
  const runId=randomUUID(),approvalId=randomUUID();
  const created=await client.query(
    "INSERT INTO runs(id,tenant_id,device_id,kind,mode,prompt,cwd,session_id,action_hash,request_key,status) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,'waiting_for_approval') ON CONFLICT (tenant_id,request_key) DO NOTHING RETURNING id",
    [runId,tenantId,body.deviceId,kind,mode,prompt,cwd,sessionId,digest,requestKey]);
  if(!created.rowCount){
    const retry=await client.query("SELECT id,action_hash,status FROM runs WHERE request_key=$1",[requestKey]);
    if(retry.rows[0]?.action_hash===digest)
      return {runId:retry.rows[0].id,status:retry.rows[0].status,reused:true};
    throw httpError(409,"Request collision; please retry");
  }
  await client.query(
    "INSERT INTO approvals(id,tenant_id,run_id,device_id,kind,description,action_hash,status,expires_at) VALUES($1,$2,$3,$4,'run',$5,$6,'pending',now()+interval '15 minutes')",
    [approvalId,tenantId,runId,body.deviceId,prompt,digest]);
  await audit(client,tenantId,subject,"run.requested",runId,{kind,mode});
  return {runId,approvalId,actionHash:digest,status:"waiting_for_approval"};
}
export async function listRuns(client) {
  const {rows}=await client.query(
    "SELECT id,device_id,kind,mode,status,created_at,updated_at,error FROM runs ORDER BY created_at DESC LIMIT 100");
  return rows;
}
export async function runDetail(client,id) {
  if(!isUUID(id))throw httpError(400,"Invalid run ID");
  const {rows}=await client.query(
    "SELECT id,device_id,kind,mode,prompt,cwd,session_id,status,result,error,created_at,updated_at FROM runs WHERE id=$1",[id]);
  if(!rows[0])throw httpError(404,"Run not found");
  return rows[0];
}
export async function listApprovals(client) {
  const {rows}=await client.query(
    "SELECT id,run_id,device_id,kind,description,action_hash,requested_at,expires_at FROM approvals WHERE status='pending' AND expires_at>now() ORDER BY requested_at DESC LIMIT 100");
  return rows;
}
export async function decideApproval(client,tenantId,subject,id,body) {
  if(!isUUID(id)||typeof body?.approve!=="boolean"||
      typeof body?.expectedActionHash!=="string"||
      !/^[0-9a-f]{64}$/.test(body.expectedActionHash))
    throw httpError(400,"Invalid approval decision");
  const desired=body.approve?"approved":"denied";
  const {rows}=await client.query(
    "UPDATE approvals SET status=$1,decided_at=now(),decided_by=$2 WHERE id=$3 AND status='pending' AND action_hash=$4 AND expires_at>now() RETURNING run_id,kind,action_hash",
    [desired,subject,id,body.expectedActionHash]);
  if(!rows[0])throw httpError(409,"Approval expired, changed, or already decided");
  const item=rows[0], status=item.kind==="run"?
    (body.approve?"queued":"denied"):(body.approve?"running":"failed");
  const updated=await client.query(
    "UPDATE runs SET status=$1,updated_at=now() WHERE id=$2 AND status=$3 RETURNING id",
    [status,item.run_id,item.kind==="run"?"waiting_for_approval":"waiting_for_tool"]);
  if(!updated.rowCount)throw httpError(409,"The original agent state changed");
  await audit(client,tenantId,subject,
    body.approve?"approval.approved":"approval.denied",item.run_id,
    {approvalId:id,kind:item.kind,actionHash:item.action_hash});
  return {runId:item.run_id,decision:desired};
}
export async function claimRun(client,tenantId,deviceId) {
  // Serialize claims by one device across replicas, including overlapping POSTs.
  await client.query("SELECT pg_advisory_xact_lock(hashtextextended($1,0))",[deviceId]);
  await client.query(
    "UPDATE runs SET status='needs_recovery',updated_at=now() WHERE device_id=$1 AND status IN ('running','waiting_for_tool') AND lease_expires_at<now()",
    [deviceId]);
  const active=await client.query(
    "SELECT id FROM runs WHERE device_id=$1 AND status IN ('running','waiting_for_tool') LIMIT 1",[deviceId]);
  if(active.rowCount)return {run:null,reason:"active_run"};
  const {rows}=await client.query(
    "SELECT id,kind,mode,prompt,cwd,session_id FROM runs WHERE device_id=$1 AND status='queued' ORDER BY created_at FOR UPDATE SKIP LOCKED LIMIT 1",
    [deviceId]);
  if(!rows[0])return {run:null};
  const leaseToken=randomUUID();
  await client.query(
    "UPDATE runs SET status='running',lease_token=$1,lease_version=lease_version+1,lease_expires_at=now()+interval '2 minutes',updated_at=now() WHERE id=$2",
    [leaseToken,rows[0].id]);
  await audit(client,tenantId,deviceId,"run.claimed",rows[0].id);
  return {run:{...rows[0],leaseToken,leaseSeconds:120}};
}
export async function leaseRun(client,tenantId,deviceId,runId,leaseToken,operation) {
  if(!isUUID(runId)||!isUUID(leaseToken))
    throw httpError(400,"Invalid run lease");
  const {rows}=await client.query(
    "SELECT id,status FROM runs WHERE id=$1 AND device_id=$2 AND lease_token=$3 AND lease_expires_at>now() AND status IN ('running','waiting_for_tool') FOR UPDATE",
    [runId,deviceId,leaseToken]);
  if(!rows[0])throw httpError(409,"Run lease expired or superseded");
  return operation(rows[0]);
}
export async function renewLease(client,deviceId,runId,leaseToken) {
  return leaseRun(client,null,deviceId,runId,leaseToken,async()=>{
    await client.query(
      "UPDATE runs SET lease_expires_at=now()+interval '2 minutes' WHERE id=$1",[runId]);
    return {leaseSeconds:120};
  });
}
export async function finishRun(client,tenantId,deviceId,runId,body) {
  if(typeof body?.ok!=="boolean")throw httpError(400,"Result status required");
  return leaseRun(client,tenantId,deviceId,runId,body.leaseToken,async()=>{
    if(body.result!=null&&JSON.stringify(body.result).length>16000)
      throw httpError(413,"Run result too large");
    const result=body.ok?body.result??{}:null;
    const error=body.ok?null:String(body.error||"Provider execution failed").slice(0,500);
    await client.query(
      "UPDATE runs SET status=$1,result=$2::jsonb,error=$3,lease_expires_at=NULL,updated_at=now() WHERE id=$4",
      [body.ok?"completed":"failed",JSON.stringify(result),error,runId]);
    await audit(client,tenantId,deviceId,body.ok?"run.completed":"run.failed",runId);
    return {status:body.ok?"completed":"failed"};
  });
}
export async function requestToolApproval(client,tenantId,deviceId,runId,body) {
  const description=text(body?.description,1200,"tool permission");
  const requestId=text(body?.requestId,100,"provider permission ID");
  const hash=hexSha256(JSON.stringify({runId,requestId,description}));
  return leaseRun(client,tenantId,deviceId,runId,body.leaseToken,async row=>{
    if(row.status!=="running")throw httpError(409,"Agent is already awaiting permission");
    const pending=await client.query(
      "SELECT count(*)::int AS count FROM approvals WHERE run_id=$1 AND kind='tool'",[runId]);
    if(pending.rows[0].count>=40)throw httpError(429,"Too many tool permission requests");
    const approvalId=randomUUID();
    await client.query(
      "INSERT INTO approvals(id,tenant_id,run_id,device_id,kind,description,action_hash,status,expires_at) VALUES($1,$2,$3,$4,'tool',$5,$6,'pending',now()+interval '3 minutes')",
      [approvalId,tenantId,runId,deviceId,description,hash]);
    await client.query(
      "UPDATE runs SET status='waiting_for_tool',updated_at=now() WHERE id=$1",[runId]);
    await audit(client,tenantId,deviceId,"tool.permission.requested",runId,
      {approvalId,actionHash:hash});
    return {approvalId,actionHash:hash,expiresInSeconds:180};
  });
}
export async function toolApprovalStatus(client,deviceId,approvalId) {
  if(!isUUID(approvalId))throw httpError(400,"Invalid tool permission");
  const {rows}=await client.query(
    "SELECT a.status,a.expires_at FROM approvals a JOIN runs r ON r.id=a.run_id WHERE a.id=$1 AND a.kind='tool' AND a.device_id=$2",
    [approvalId,deviceId]);
  if(!rows[0])throw httpError(404,"Permission not found");
  return {state:rows[0].status==="pending"&&new Date(rows[0].expires_at).getTime()<=Date.now()?
    "expired":rows[0].status};
}

const EVENT_KINDS=new Set(["agent_delta","status","turn_completed","warning"]);
export async function appendRunEvent(client,tenantId,deviceId,runId,body) {
  if(!EVENT_KINDS.has(body?.kind)||typeof body.text!=="string"||
      body.text.length>1800||/[\x00-\x08\x0b\x0c\x0e-\x1f]/.test(body.text))
    throw httpError(400,"Invalid provider event");
  return leaseRun(client,tenantId,deviceId,runId,body.leaseToken,async()=>{
    const count=await client.query(
      "SELECT count(*)::int AS count FROM run_events WHERE run_id=$1",[runId]);
    if(count.rows[0].count>=500)throw httpError(429,"Provider event quota exceeded");
    const {rows}=await client.query(
      "INSERT INTO run_events(tenant_id,run_id,kind,text) VALUES($1,$2,$3,$4) RETURNING id",
      [tenantId,runId,body.kind,body.text]);
    return {recorded:true,eventId:rows[0].id};
  });
}
export async function listRunEvents(client,runId,after=0) {
  if(!isUUID(runId)||!Number.isSafeInteger(after)||after<0)
    throw httpError(400,"Invalid event cursor or run ID");
  const run=await client.query("SELECT id FROM runs WHERE id=$1",[runId]);
  if(!run.rowCount)throw httpError(404,"Run not found");
  const {rows}=await client.query(
    "SELECT id,kind,text,created_at FROM run_events WHERE run_id=$1 AND id>$2 ORDER BY id LIMIT 100",
    [runId,after]);
  return {events:rows,nextCursor:rows.length?rows.at(-1).id:after};
}
