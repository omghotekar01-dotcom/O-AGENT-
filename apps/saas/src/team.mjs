import {createHash,randomBytes,randomUUID} from "node:crypto";
import {audit} from "./store.mjs";
import {httpError} from "./operations.mjs";

export const ROLE_LEVEL=Object.freeze({viewer:1,operator:2,owner:3});
const tokenPattern=/^oti_[A-Za-z0-9_-]{43}$/;

export async function listWorkspaces(client,identity){
  const {rows}=await client.query(
    "SELECT m.tenant_id,m.role,m.created_at,t.display_name FROM tenant_members m JOIN tenants t ON t.id=m.tenant_id WHERE m.issuer=$1 AND m.subject=$2 ORDER BY m.created_at,m.tenant_id LIMIT 30",
    [identity.issuer,identity.subject]);
  return rows;
}
export async function listTeamMembers(client){
  const {rows}=await client.query(
    "SELECT issuer,subject,role,created_at FROM tenant_members ORDER BY created_at LIMIT 30");
  return rows;
}
export async function createTeamInvite(client,tenantId,subject,role){
  if(!["operator","viewer"].includes(role))
    throw httpError(400,"Invite role must be operator or viewer");
  const count=await client.query(
    "SELECT count(*)::int AS n FROM tenant_members WHERE tenant_id=$1",[tenantId]);
  if(count.rows[0].n>=20)throw httpError(409,"Team member limit reached");
  const active=await client.query(
    "SELECT count(*)::int AS n FROM pending_team_invites WHERE tenant_id=$1 AND redeemed_at IS NULL AND expires_at>now()",[tenantId]);
  if(active.rows[0].n>=10)throw httpError(429,"Too many outstanding invitations");
  const inviteToken="oti_"+randomBytes(32).toString("base64url");
  const hash=createHash("sha256").update(inviteToken).digest();
  const id=randomUUID();
  await client.query(
    "INSERT INTO pending_team_invites(id,tenant_id,token_hash,role,created_by,expires_at) VALUES($1,$2,$3,$4,$5,now()+interval '15 minutes')",
    [id,tenantId,hash,role,subject.slice(0,160)]);
  await audit(client,tenantId,subject,"team.invite.created",id,{role});
  return {inviteToken,role,expiresInSeconds:900};
}
export async function redeemTeamInvite(pool,identity,inviteToken){
  if(!identity||typeof identity.issuer!=="string"||
    !identity.issuer||typeof identity.subject!=="string"||!identity.subject)
    throw httpError(401,"Signed-in identity required");
  if(typeof inviteToken!=="string"||!tokenPattern.test(inviteToken))
    throw httpError(400,"Invalid team invite");
  const hash=createHash("sha256").update(inviteToken).digest();
  const client=await pool.connect();
  try{
    await client.query("BEGIN");
    await client.query("SELECT set_config('oagent.identity_issuer',$1,true)",[identity.issuer]);
    await client.query("SELECT set_config('oagent.identity_subject',$1,true)",[identity.subject]);
    const result=await client.query(
      "SELECT id,tenant_id,role FROM pending_team_invites WHERE token_hash=$1 AND redeemed_at IS NULL AND expires_at>now() FOR UPDATE",
      [hash]);
    const invite=result.rows[0];
    if(!invite)throw httpError(409,"Team invitation is expired or already used");
    await client.query("SELECT set_config('oagent.tenant_id',$1,true)",[invite.tenant_id]);
    const own=await client.query(
      "SELECT role FROM tenant_members WHERE tenant_id=$1 AND issuer=$2 AND subject=$3",
      [invite.tenant_id,identity.issuer,identity.subject]);
    if(own.rowCount)throw httpError(409,"Already a member of this workspace");
    const count=await client.query(
      "SELECT count(*)::int AS n FROM tenant_members WHERE tenant_id=$1",[invite.tenant_id]);
    if(count.rows[0].n>=20)throw httpError(409,"Team member limit reached");
    await client.query(
      "INSERT INTO tenant_members(tenant_id,issuer,subject,role) VALUES($1,$2,$3,$4)",
      [invite.tenant_id,identity.issuer,identity.subject,invite.role]);
    await client.query(
      "UPDATE pending_team_invites SET redeemed_at=now(),redeemed_by=$2 WHERE id=$1",
      [invite.id,identity.subject.slice(0,160)]);
    await audit(client,invite.tenant_id,identity.subject,"team.member.joined",null,
      {role:invite.role});
    await client.query("COMMIT");
    return {joined:true,workspaceId:invite.tenant_id,role:invite.role};
  }catch(error){
    try{await client.query("ROLLBACK");}catch{}
    throw error;
  }finally{client.release();}
}
export async function removeTeamMember(client,tenantId,actor,body){
  if(typeof body?.issuer!=="string"||!body.issuer||
     typeof body?.subject!=="string"||!body.subject||
     body.issuer.length>500||body.subject.length>500)
    throw httpError(400,"Valid team member identity required");
  const selected=await client.query(
    "SELECT role FROM tenant_members WHERE tenant_id=$1 AND issuer=$2 AND subject=$3 FOR UPDATE",
    [tenantId,body.issuer,body.subject]);
  if(!selected.rowCount)throw httpError(404,"Team member not found");
  if(selected.rows[0].role==="owner")throw httpError(403,"Owner cannot be removed");
  await client.query(
    "DELETE FROM tenant_members WHERE tenant_id=$1 AND issuer=$2 AND subject=$3",
    [tenantId,body.issuer,body.subject]);
  await audit(client,tenantId,actor,"team.member.removed",null,
    {role:selected.rows[0].role});
  return {removed:true};
}
export async function renameWorkspace(client,tenantId,actor,name){
  if(typeof name!=="string"||name.trim().length<2||name.trim().length>80||
    /[\x00-\x1f\x7f]/.test(name))
    throw httpError(400,"Workspace name must be 2–80 visible characters");
  const clean=name.trim();
  await client.query("UPDATE tenants SET display_name=$1 WHERE id=$2",[clean,tenantId]);
  await audit(client,tenantId,actor,"team.workspace.renamed",null);
  return {name:clean};
}
