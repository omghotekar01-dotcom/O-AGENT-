/**
 * Non-destructive recovery of a partially initialized PostgreSQL cluster.
 * The official postgres initdb scripts run exactly ONCE. If init-postgres.sh
 * failed on the first boot, Docker restarts a healthy postgres cluster while
 * O-AGENT databases/roles never get created. Re-running Compose cannot help.
 *
 * This helper inspects the cluster first, validates existing ownership and
 * role privileges, then requires verified AES-GCM-encrypted pg_dumpall output
 * before adding ONLY missing O-AGENT databases, roles and safe grants.
 * Nothing deletes the existing PostgreSQL volume or changes Tailscale routes.
 */
import {spawn} from "node:child_process";
import {randomBytes} from "node:crypto";
import {readFile,mkdir,writeFile,rm} from "node:fs/promises";
import {homedir} from "node:os";
import {dirname,join} from "node:path";
import {fileURLToPath} from "node:url";
import {encryptBackup,verifyBackup} from "./backup-crypto.mjs";
import {parseRoleSecrets} from "./repair-db-auth.mjs";

const dir=dirname(fileURLToPath(import.meta.url));
const compose=["compose","--env-file",".env.local","-f","compose.yaml"];
const roleOwners=Object.freeze({
  oagent_runtime:null,
  oagent_migrator:"oagent",
  oagent_keycloak:"keycloak",
});
const dbOwners=Object.freeze({oagent:"oagent_migrator",keycloak:"oagent_keycloak"});
const roleKeys=Object.keys(roleOwners),dbKeys=Object.keys(dbOwners);
const sourceMeta=Object.freeze({stage:"inspect-only",safe:true});

function rows(raw,fields){
  if(!raw.trim())return [];
  return raw.trim().split(/\r?\n/).map(line=>{
    const parts=line.split("|");
    if(parts.length!==fields)throw Error("Unexpected private PostgreSQL catalog response");
    return parts;
  });
}
export function classifyPilotCluster({databaseRows=[],roleRows=[]}={}){
  const databases={},roles={};
  for(const [name,owner] of databaseRows){
    if(!Object.hasOwn(dbOwners,name)||Object.hasOwn(databases,name))
      throw Error("Unexpected private database catalog");
    if(owner!==dbOwners[name])
      throw Error("Existing pilot database has a different owner; manual review required");
    databases[name]=owner;
  }
  for(const [name,canLogin,isSuper,bypassRls,createRole,createDb,replication] of roleRows){
    if(!Object.hasOwn(roleOwners,name)||Object.hasOwn(roles,name))
      throw Error("Unexpected private role catalog");
    if(canLogin!=="t"||isSuper!=="f"||bypassRls!=="f"||
       createRole!=="f"||createDb!=="f"||replication!=="f")
      throw Error("Existing pilot role has unsafe privileges; manual review required");
    roles[name]=true;
  }
  for(const [db,owner] of Object.entries(databases))
    if(!roles[owner])
      throw Error("Existing pilot DB owner role is absent; manual recovery required");
  return {
    missingDatabases:dbKeys.filter(name=>!databases[name]),
    missingRoles:roleKeys.filter(name=>!roles[name]),
    ready:dbKeys.every(x=>databases[x])&&roleKeys.every(x=>roles[x]),
  };
}
export function buildBootstrapSql(state,secrets){
  if(!Array.isArray(state.missingRoles)||!Array.isArray(state.missingDatabases))
    throw Error("Invalid pilot bootstrap plan");
  const roleStatements=state.missingRoles.map(role=>{
    if(!Object.hasOwn(roleOwners,role)||!/^[a-f0-9]{48}$/.test(secrets[role]||""))
      throw Error("Unsafe or missing generated pilot database credential");
    return "CREATE ROLE "+role+" LOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOREPLICATION PASSWORD '"+secrets[role]+"';";
  });
  const dbStatements=state.missingDatabases.map(db=>{
    if(!Object.hasOwn(dbOwners,db))
      throw Error("Unexpected database requested in bootstrap");
    return "CREATE DATABASE "+db+" OWNER "+dbOwners[db]+";";
  });
  // Roles are created atomically. CREATE DATABASE cannot be inside BEGIN.
  return {
    roleSql:"BEGIN;\n"+roleStatements.join("\n")+"\nCOMMIT;",
    dbSql:dbStatements,
    grantSql:"GRANT CONNECT ON DATABASE oagent TO oagent_runtime;",
    schemaSql:[
      "GRANT USAGE ON SCHEMA public TO oagent_runtime;",
      "ALTER DEFAULT PRIVILEGES FOR ROLE oagent_migrator IN SCHEMA public GRANT SELECT,INSERT,UPDATE,DELETE ON TABLES TO oagent_runtime;",
      "ALTER DEFAULT PRIVILEGES FOR ROLE oagent_migrator IN SCHEMA public GRANT USAGE,SELECT ON SEQUENCES TO oagent_runtime;",
    ].join("\n"),
  };
}
function runDocker(args,{input="",spawnImpl=spawn}={}){
  return new Promise((resolve,reject)=>{
    const child=spawnImpl("docker",["compose","--env-file",".env.local",
      "-f","compose.yaml","exec","-T","--user","postgres","db",
      "psql","-X","-A","-t","-v","ON_ERROR_STOP=1","-U","postgres",...args],
      {cwd:dir,windowsHide:true,stdio:["pipe","pipe","pipe"],timeout:35000});
    let output="",overflow=false,done=false;
    child.stdout.on("data",chunk=>{
      output+=chunk.toString("utf8");
      if(output.length>30000){overflow=true;child.kill();}
    });
    // Suppress stderr to ensure SQL passwords are never reflected in console.
    child.stderr.resume();
    child.once("error",()=>{if(!done){done=true;reject(Error("Cannot connect to the O-AGENT PostgreSQL container"));}});
    child.once("close",code=>{
      if(done)return;
      done=true;
      if(code!==0||overflow)reject(Error("PostgreSQL bootstrap query failed (no credentials displayed)"));
      else resolve(output.trim());
    });
    child.stdin.on("error",()=>{});
    child.stdin.end(input+"\n");
  });
}
export async function inspectPilotCluster({query=runDocker}={}){
  const user=(await query(["-d","postgres"],{input:"SELECT current_user;"})).trim();
  if(user!=="postgres")throw Error("PostgreSQL administrator identity is unavailable");
  const databaseRows=rows(await query(["-d","postgres"],{input:
    "SELECT datname,pg_get_userbyid(datdba) FROM pg_database WHERE datname IN ('oagent','keycloak') ORDER BY datname;"}),2);
  const roleRows=rows(await query(["-d","postgres"],{input:
    "SELECT rolname,rolcanlogin,rolsuper,rolbypassrls,rolcreaterole,rolcreatedb,rolreplication FROM pg_roles WHERE rolname IN ('oagent_runtime','oagent_migrator','oagent_keycloak') ORDER BY rolname;"}),7);
  return classifyPilotCluster({databaseRows,roleRows});
}
export async function backupPilotCluster({destination,password,spawnImpl=spawn}={}){
  if(typeof destination!=="string"||!password||password.length<20)
    throw Error("Encrypted cluster backup destination and key required");
  // pg_dumpall includes global roles, current role passwords and every local
  // database; unlike pg_dump for named DBs it works when those DBs are absent.
  const args=[...compose,"exec","-T","--user","postgres","db",
    "pg_dumpall","-U","postgres"];
  const child=spawnImpl("docker",args,{cwd:dir,stdio:["ignore","pipe","pipe"],
    windowsHide:true,timeout:180000});
  child.stderr.resume();
  const exit=new Promise((resolve,reject)=>{
    child.once("error",()=>reject(Error("Cannot launch encrypted cluster backup")));
    child.once("close",code=>code===0?resolve():reject(Error("PostgreSQL cluster backup failed")));
  });
  try{
    await encryptBackup(child.stdout,destination,password);
    await exit;
  }catch{
    child.kill();
    await rm(destination,{force:true});
    throw Error("Full-cluster backup failed. No database change was attempted.");
  }
  return destination;
}
export async function bootstrapPilotDb({apply=false,inspect=inspectPilotCluster,
  query=runDocker,backup=backupPilotCluster,verify=verifyBackup,
  read=readFile,secretPath=join(dir,".env.local"),
  keyDirectory=join(homedir(),".oagent-recovery-keys"),
  backupDirectory=join(dir,"backups")}={}){
  const state=await inspect({query});
  if(state.ready)return {status:"ready",...state};
  if(!apply)return {status:"incomplete",...state};
  const secrets=parseRoleSecrets(await read(secretPath,"utf8"));
  const plan=buildBootstrapSql(state,secrets);
  const stamp=new Date().toISOString().replace(/[:.]/g,"-");
  await mkdir(keyDirectory,{recursive:true,mode:0o700});
  await mkdir(backupDirectory,{recursive:true,mode:0o700});
  const keyPath=join(keyDirectory,"pre-bootstrap-"+stamp+".key");
  const archivePath=join(backupDirectory,"pre-bootstrap-"+stamp+".cluster.oagent.enc");
  const password=randomBytes(40).toString("base64url");
  await writeFile(keyPath,password+"\n",{flag:"wx",mode:0o600});
  await backup({destination:archivePath,password});
  await verify(archivePath,password);
  // Race guard: refuse if another process changed role/DB inventory while the
  // encrypted backup ran. Do not silently replace existing applications.
  const before=await inspect({query});
  if(JSON.stringify(before)!==JSON.stringify(state))
    throw Error("PostgreSQL inventory changed during backup; no bootstrap SQL executed");
  if(state.missingRoles.length)
    await query(["-d","postgres"],{input:plan.roleSql});
  for(const command of plan.dbSql)
    await query(["-d","postgres"],{input:command});
  await query(["-d","postgres"],{input:plan.grantSql});
  await query(["-d","oagent"],{input:plan.schemaSql});
  const after=await inspect({query});
  if(!after.ready)
    throw Error("PostgreSQL bootstrap was only partially completed; preserve encrypted backup");
  return {status:"bootstrapped",createdRoles:state.missingRoles,
    createdDatabases:state.missingDatabases,archivePath,keyPath};
}
async function main(){
  const args=process.argv.slice(2);
  if(args.length>1||(args[0]&&args[0]!=="--apply")){
    console.error("[FIX] Usage: node bootstrap-db.mjs [--apply]");
    process.exitCode=1;return;
  }
  try{
    const result=await bootstrapPilotDb({apply:args[0]==="--apply"});
    if(result.status==="ready"){
      console.log("[PASS] O-AGENT PostgreSQL databases and roles are complete.");
    }else if(result.status==="incomplete"){
      console.log("[FIX] Incomplete initial PostgreSQL setup: missing roles: "+
        (result.missingRoles.join(", ")||"none")+"; missing databases: "+
        (result.missingDatabases.join(", ")||"none"));
      console.log("Recovery will first encrypt and verify the full existing PostgreSQL cluster.");
    }else{
      console.log("[PASS] Missing O-AGENT roles/databases created without deleting existing volumes.");
      console.log("Encrypted full-cluster backup: "+result.archivePath);
      console.log("Separate private recovery key: "+result.keyPath);
      console.log("Next step: verify/repair scoped database role passwords.");
    }
  }catch{
    console.error("[FIX] PostgreSQL bootstrap stopped. Verify local Docker admin access and expected ownership.");
    console.error("No Docker volume or Tailscale route was removed. Preserve any encrypted recovery backup.");
    process.exitCode=1;
  }
}
if(process.argv[1]&&fileURLToPath(import.meta.url)===process.argv[1])
  await main();
