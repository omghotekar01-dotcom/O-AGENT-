import {randomUUID} from "node:crypto";
import pg from "pg";
import {readFile} from "node:fs/promises";
import {fileURLToPath} from "node:url";
const {Pool}=pg;
export const createPool=config=>new Pool({
  connectionString:config.databaseUrl,max:10,
  connectionTimeoutMillis:5000,idleTimeoutMillis:30000,
  application_name:"oagent_saas",
});
export async function migrate(pool) {
  const sql=await readFile(fileURLToPath(new URL("../sql/001_init.sql",import.meta.url)),"utf8");
  const client=await pool.connect();
  try {await client.query("BEGIN");await client.query(sql);await client.query("COMMIT");}
  catch(error){await client.query("ROLLBACK");throw error;}
  finally{client.release();}
}
/** All tenant queries use a single client with transaction-scoped RLS context. */
export async function withTenant(pool,tenantId,fn) {
  const client=await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query("SELECT set_config('oagent.tenant_id',$1,true)",[tenantId]);
    const value=await fn(client,tenantId);
    await client.query("COMMIT");
    return value;
  }catch(error){
    try{await client.query("ROLLBACK");}catch{}
    throw error;
  }finally{client.release();}
}
/**
 * Separate verified identities cannot choose a tenant ID. Initial v1 uses
 * one private workspace per OIDC identity; org membership must be implemented
 * before advertising shared-enterprise workspaces.
 */
export async function withIdentity(pool,identity,fn) {
  if(!identity || typeof identity.issuer!=="string" ||
     typeof identity.subject!=="string")
    throw Object.assign(Error("Verified identity required"),{status:401});
  const client=await pool.connect();
  try{
    await client.query("BEGIN");
    // Serialize same-subject first login and avoid orphan tenant creation.
    await client.query("SELECT pg_advisory_xact_lock(hashtextextended($1,0))",[
      identity.issuer + "\n" + identity.subject]);
    let found=await client.query(
      "SELECT tenant_id FROM identities WHERE issuer=$1 AND subject=$2",
      [identity.issuer,identity.subject]);
    let tenantId=found.rows[0]?.tenant_id;
    if(!tenantId){
      tenantId=randomUUID();
      await client.query("INSERT INTO tenants(id) VALUES($1)",[tenantId]);
      await client.query(
        "INSERT INTO identities(issuer,subject,tenant_id) VALUES($1,$2,$3)",
        [identity.issuer,identity.subject,tenantId]);
    }
    await client.query("SELECT set_config('oagent.tenant_id',$1,true)",[tenantId]);
    const value=await fn(client,tenantId);
    await client.query("COMMIT");
    return value;
  }catch(error){
    try{await client.query("ROLLBACK");}catch{}
    throw error;
  }finally{client.release();}
}
export async function audit(client,tenantId,actor,action,targetId,detail={}) {
  await client.query("INSERT INTO audit_events(tenant_id,actor,action,target_id,detail) VALUES($1,$2,$3,$4,$5::jsonb)",
    [tenantId,String(actor).slice(0,160),action,targetId,
      JSON.stringify(detail)]);
}

/** Launch gate: never serve tenants from a superuser/BYPASSRLS pool. */
export async function assertTenantDatabaseSecurity(pool) {
  const role=await pool.query(
    "SELECT rolsuper,rolbypassrls FROM pg_roles WHERE rolname=current_user");
  if(role.rowCount!==1||role.rows[0].rolsuper||role.rows[0].rolbypassrls)
    throw Error("Unsafe PostgreSQL runtime role: superuser/BYPASSRLS forbidden");
  // Table owners can change RLS policy, even with FORCE RLS.
  const owners=await pool.query(
    "SELECT relname FROM pg_class WHERE relname=ANY($1::text[]) AND relkind='r' AND pg_has_role(current_user,relowner,'MEMBER')",
    [["devices","runs","approvals","run_events","audit_events"]]);
  if(owners.rowCount)throw Error("Unsafe runtime role: owner of tenant tables");
  const guard=await pool.query(
    "SELECT relname,relrowsecurity,relforcerowsecurity FROM pg_class WHERE relname=ANY($1::text[]) AND relkind='r'",
    [["devices","runs","approvals","run_events","audit_events"]]);
  if(guard.rowCount!==5||guard.rows.some(x=>!x.relrowsecurity||
      !x.relforcerowsecurity))
    throw Error("Tenant isolation tables have missing or disabled FORCE RLS");
  return {ok:true};
}
