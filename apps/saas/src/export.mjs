import {httpError} from "./operations.mjs";

/** Export only the signed-in owner's data through FORCE-RLS transactions.
 * Device private signing keys, OTPs, access tokens, push encryption secrets,
 * service database credentials and provider auth material are NEVER exported.
 * Bounded responses avoid downloading unbounded confidential history.
 */
export async function exportOwnerData(client,identity,{limit=2000,maxBytes=8_000_000}={}){
  if(!identity||typeof identity.issuer!=="string"||
     typeof identity.subject!=="string")
    throw httpError(401,"Verified owner identity required");
  const queries={
    devices:"SELECT id,name,capabilities,workspace_root,created_at,last_seen_at,revoked_at FROM devices ORDER BY created_at",
    runs:"SELECT id,device_id,kind,mode,prompt,cwd,session_id,action_hash,status,result,error,created_at,updated_at FROM runs ORDER BY created_at",
    approvals:"SELECT id,run_id,device_id,kind,description,action_hash,status,requested_at,expires_at,decided_at,decided_by FROM approvals ORDER BY requested_at",
    activity:"SELECT id,run_id,kind,text,created_at FROM run_events ORDER BY id",
    audit:"SELECT id,actor,action,target_id,created_at,detail FROM audit_events ORDER BY id",
  };
  const data={format:"oagent-tenant-export-v1",
    exportedAt:new Date().toISOString(),
    identity:{issuer:identity.issuer,subject:identity.subject}};
  for(const [name,sql] of Object.entries(queries)){
    const {rows}=await client.query(sql+" LIMIT $1",[limit+1]);
    if(rows.length>limit)throw httpError(413,
      "Workspace export exceeds the safe single-download limit. Use encrypted PostgreSQL backup for complete archives.");
    data[name]=rows;
  }
  const serialized=JSON.stringify(data);
  if(Buffer.byteLength(serialized,"utf8")>maxBytes)
    throw httpError(413,"Workspace export exceeds the secure browser download limit");
  return data;
}
