import {createHash,createHmac,pbkdf2Sync,randomBytes,timingSafeEqual} from "node:crypto";
import {spawn} from "node:child_process";
import {readFile,mkdir,writeFile} from "node:fs/promises";
import {homedir} from "node:os";
import {dirname,join} from "node:path";
import {fileURLToPath} from "node:url";
import {backupPilot} from "./backup.mjs";
import {verifyBackup} from "./backup-crypto.mjs";

const directory=dirname(fileURLToPath(import.meta.url));
const names=Object.freeze({
  oagent_runtime:"OAGENT_RUNTIME_PASSWORD",
  oagent_migrator:"OAGENT_MIGRATION_PASSWORD",
  oagent_keycloak:"OAGENT_KEYCLOAK_DB_PASSWORD",
});
const psqlArgs=["compose","--env-file",".env.local","-f","compose.yaml",
  "exec","-T","--user","postgres","db","psql","-X","-A","-t",
  "-v","ON_ERROR_STOP=1","-U","postgres","-d","postgres"];

export function parseRoleSecrets(source){
  const result={};
  for(const [role,name] of Object.entries(names)){
    const value=source.match(new RegExp("^"+name+"=([a-f0-9]{48})$","m"))?.[1];
    if(!value)throw Error("Missing or invalid private role secret: "+name);
    result[role]=value;
  }
  return result;
}

/** Validate a local pilot's stored PostgreSQL SCRAM/MD5 role verifier.
 * Never return or log either the plaintext credential or stored verifier.
 */
export function matchesRolePassword(password,role,verifier){
  if(typeof password!=="string"||typeof verifier!=="string")return false;
  if(verifier.startsWith("md5"))
    return verifier==="md5"+createHash("md5").update(password+role).digest("hex");
  const parts=verifier.match(/^SCRAM-SHA-256\$(\d+):([A-Za-z0-9+/=]+)\$([A-Za-z0-9+/=]+):([A-Za-z0-9+/=]+)$/);
  if(!parts)return false;
  const rounds=Number(parts[1]);
  if(!Number.isSafeInteger(rounds)||rounds<4096||rounds>1000000)return false;
  try{
    const salt=Buffer.from(parts[2],"base64");
    const key=pbkdf2Sync(password,salt,rounds,32,"sha256");
    const client=createHmac("sha256",key).update("Client Key").digest();
    const stored=createHash("sha256").update(client).digest();
    const expected=Buffer.from(parts[3],"base64");
    return stored.length===expected.length&&timingSafeEqual(stored,expected);
  }catch{return false;}
}
async function psql(sql,{spawnImpl=spawn}={}){
  return new Promise((resolve,reject)=>{
    const child=spawnImpl("docker",psqlArgs,{cwd:directory,
      stdio:["pipe","pipe","pipe"],timeout:30000,windowsHide:true});
    let output="",excess=false;
    child.stdout.on("data",chunk=>{
      output+=chunk.toString("utf8");
      if(output.length>30000){excess=true;child.kill();}
    });
    // Suppress raw errors: database URLs, roles, and private paths may be present.
    child.stderr.on("data",()=>{});
    child.on("error",()=>reject(Error("Cannot connect to the private pilot database container")));
    child.on("close",code=>code===0&&!excess?resolve(output.trim()):
      reject(Error("PostgreSQL local-admin query failed; inspect Docker Desktop and DB health")));
    child.stdin.on("error",()=>{});
    child.stdin.end(sql+"\n");
  });
}
async function inspectRoles(query=psql){
  const operator=(await query("SELECT current_user;")).trim();
  if(operator!=="postgres")throw Error("Database administration identity is not postgres; refusing changes");
  const dbs=(await query("SELECT datname FROM pg_database WHERE datname IN ('oagent','keycloak') ORDER BY datname;")).split("\n").filter(Boolean);
  if(dbs.join(",")!=="keycloak,oagent")throw Error("Expected O-AGENT and Keycloak databases were not both found");
  const rows=(await query("SELECT rolname,coalesce(rolpassword,''),rolsuper,rolbypassrls FROM pg_authid WHERE rolname IN ('oagent_runtime','oagent_migrator','oagent_keycloak') ORDER BY rolname;"))
    .split("\n").filter(Boolean).map(line=>line.split("|"));
  if(rows.length!==3||rows.some(x=>x.length!==4||!(x[0] in names)||x[2]!=="f"||x[3]!=="f"))
    throw Error("Unexpected pilot database roles or unsafe elevated roles; refusing changes");
  return Object.fromEntries(rows.map(x=>[x[0],x[1]]));
}
export async function repairDbAuth({apply=false,read=readFile,
  inspect=inspectRoles,query=psql,backup=backupPilot,
  verify=verifyBackup,
  keyDirectory=join(homedir(),".oagent-recovery-keys"),
  backupDirectory=join(directory,"backups")}={}){
  const secrets=parseRoleSecrets(await read(join(directory,".env.local"),"utf8"));
  const saved=await inspect(query);
  const mismatch=Object.keys(names).filter(role=>!
    matchesRolePassword(secrets[role],role,saved[role]));
  if(!mismatch.length)return {status:"already-matched",changed:0};
  if(!apply)return {status:"needs-repair",roles:mismatch,changed:0};
  // A password reset preserves all tables and volumes but changes database
  // access. Require an authenticated, complete and verified encrypted backup
  // of both databases before touching even one role.
  const stamp=new Date().toISOString().replace(/[:.]/g,"-");
  const recovery=keyDirectory;
  await mkdir(recovery,{recursive:true,mode:0o700});
  const keyPath=join(recovery,"pilot-repair-"+stamp+".key");
  const passphrase=randomBytes(40).toString("base64url");
  await writeFile(keyPath,passphrase+"\n",{flag:"wx",mode:0o600});
  const backupFolder=join(backupDirectory,"pre-db-auth-repair-"+stamp);
  await backup({password:passphrase,output:backupFolder});
  for(const database of ["oagent","keycloak"])
    await verify(join(backupFolder,database+".oagent.enc"),passphrase);
  // Role names and credentials are validated allowlisted values. SQL is sent
  // via stdin, never command arguments, logs, env injection or shell history.
  const changes=mismatch.map(role=>"ALTER ROLE "+role+
    " PASSWORD '"+secrets[role]+"';").join("\n");
  await query("BEGIN;\n"+changes+"\nCOMMIT;");
  const latest=await inspect(query);
  if(mismatch.some(role=>!matchesRolePassword(secrets[role],role,latest[role])))
    throw Error("Database role verification failed after repair; preserve the encrypted backups");
  return {status:"repaired",roles:mismatch,changed:mismatch.length,
    backupFolder,keyPath};
}
async function main(){
  const flag=process.argv.slice(2);
  if(flag.length>1||(flag[0]&&flag[0]!=="--apply"))
    throw Error("Use: node repair-db-auth.mjs [--apply]");
  const result=await repairDbAuth({apply:flag[0]==="--apply"});
  if(result.status==="already-matched"){
    console.log("[PASS] Database role passwords already match local pilot settings.");return;
  }
  if(result.status==="needs-repair"){
    console.log("[FIX] Database role passwords do not match local pilot settings: "+result.roles.join(", "));
    console.log("Run node repair-db-auth.mjs --apply only after reviewing the existing database.");
    console.log("The repair first creates and verifies encrypted backups of both databases.");return;
  }
  console.log("[PASS] Reconciled "+result.changed+" O-AGENT database role password(s).");
  console.log("Encrypted backup folder: "+result.backupFolder);
  console.log("Private recovery key file (keep separately): "+result.keyPath);
  console.log("Existing tables and Docker volumes were not deleted.");
  console.log("Keycloak public issuer/redirect URLs still require port 8443 migration.");
}
if(process.argv[1]&&fileURLToPath(import.meta.url)===process.argv[1])
  main().catch(()=>{console.error(
    "[FIX] Database password repair stopped. No volume was deleted. Check Docker and keep backup files private.");
    process.exitCode=1;});
