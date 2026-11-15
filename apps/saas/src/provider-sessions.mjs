import {httpError,isUUID} from "./operations.mjs";
const SDK_KINDS=new Set(["claude_agent_turn","copilot_sdk_turn"]);
const SESSION_ID=/^[A-Za-z0-9_-]{8,120}$/;

/** Confirmed SDK-owned sessions, not arbitrary external desktop tabs.
 * The owning OIDC transaction and PostgreSQL FORCE-RLS scope every row.
 */
export async function listProviderSessions(client){
  const {rows}=await client.query(
    "SELECT recent.\"deviceId\",recent.\"deviceName\",recent.kind, "+
    "recent.\"sessionId\",recent.cwd,recent.\"lastPrompt\", "+
    "recent.preview,recent.\"updatedAt\" FROM ("+
    " SELECT DISTINCT ON (r.device_id,r.kind,r.result->>'sessionId') "+
    "r.device_id AS \"deviceId\",d.name AS \"deviceName\", "+
    "r.kind,r.result->>'sessionId' AS \"sessionId\",r.cwd, "+
    "left(r.prompt,160) AS \"lastPrompt\", "+
    "left(coalesce(r.result->>'response',r.result->>'output',''),260) "+
    "AS preview,r.updated_at AS \"updatedAt\" "+
    "FROM runs r JOIN devices d ON d.id=r.device_id "+
    "WHERE d.revoked_at IS NULL "+
    "AND r.kind IN ('claude_agent_turn','copilot_sdk_turn') "+
    "AND r.status='completed' "+
    "AND r.result->>'sessionId' ~ '^[A-Za-z0-9_-]{8,120}$' "+
    "ORDER BY r.device_id,r.kind,r.result->>'sessionId',r.updated_at DESC "+
    ") recent ORDER BY recent.\"updatedAt\" DESC LIMIT 80"
  );
  return rows;
}
export async function providerSessionHistory(client,{kind,deviceId,sessionId}){
  if(!SDK_KINDS.has(kind)||!isUUID(deviceId)||!SESSION_ID.test(sessionId))
    throw httpError(400,"Invalid saved SDK session");
  const {rows}=await client.query(
    "SELECT r.id,r.status,r.prompt,r.mode, "+
    "left(coalesce(r.result->>'response',r.result->>'output',''),2400) "+
    "AS response,r.created_at AS \"createdAt\",r.updated_at AS \"updatedAt\" "+
    "FROM runs r JOIN devices d ON d.id=r.device_id "+
    "WHERE r.device_id=$1 AND r.kind=$2 AND d.revoked_at IS NULL "+
    "AND r.status='completed' "+
    "AND (r.session_id=$3 OR r.result->>'sessionId'=$3) "+
    "ORDER BY r.created_at DESC LIMIT 30",[deviceId,kind,sessionId]
  );
  if(!rows.length)throw httpError(404,"No verified SDK conversation on this worker");
  return {turns:rows.reverse()};
}
