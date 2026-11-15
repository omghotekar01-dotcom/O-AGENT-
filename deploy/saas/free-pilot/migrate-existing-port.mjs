import {spawn,execFileSync} from "node:child_process";
import {randomBytes} from "node:crypto";
import {readFile,writeFile,copyFile,mkdir,rename} from "node:fs/promises";
import {dirname,join} from "node:path";
import {fileURLToPath} from "node:url";
import {homedir} from "node:os";
import {tailnetOrigin,renderOwnerRealm} from "./setup.mjs";
import {verifyPrivateServeAvailability} from "./start.mjs";
import {backupPilot} from "./backup.mjs";
import {verifyBackup} from "./backup-crypto.mjs";
import {repairDbAuth} from "./repair-db-auth.mjs";

const dir=dirname(fileURLToPath(import.meta.url));
const compose=["compose","--env-file",".env.local","-f","compose.yaml"];
const exec=(name,args)=>execFileSync(name,args,{
  cwd:dir,encoding:"utf8",timeout:12000,stdio:["ignore","pipe","pipe"]});
function containerCommand(args,input="",{spawnImpl=spawn}={}){
  return new Promise((resolve,reject)=>{
    const child=spawnImpl("docker",[...compose,"exec","-T","identity",...args],{
      cwd:dir,windowsHide:true,timeout:35000,stdio:["pipe","pipe","pipe"]});
    let output="",overflow=false;
    child.stdout.on("data",chunk=>{
      output+=chunk.toString("utf8");
      if(output.length>100000){overflow=true;child.kill();}
    });
    child.stderr.on("data",()=>{});
    child.once("error",()=>reject(Error("Cannot contact Keycloak container")));
    child.once("close",code=>code===0&&!overflow?resolve(output.trim()):
      reject(Error("Keycloak admin CLI failed; inspect identity readiness and credentials")));
    child.stdin.on("error",()=>{});
    child.stdin.end(input);
  });
}
export function planClientOrigin(client,from,to){
  if(client?.clientId!=="oagent-web"||client.publicClient!==true||
      !Array.isArray(client.redirectUris)||client.redirectUris.length!==1||
      !Array.isArray(client.webOrigins)||client.webOrigins.length!==1)
    throw Error("Expected O-AGENT public OIDC client was not found");
  if(client.redirectUris[0]!==from+"/"&&client.redirectUris[0]!==to+"/")
    throw Error("Existing redirect was customized; manual review required");
  if(client.webOrigins[0]!==from&&client.webOrigins[0]!==to)
    throw Error("Existing web origin was customized; manual review required");
  const logout=client.attributes?.["post.logout.redirect.uris"];
  if(logout!==from+"/"&&logout!==to+"/")
    throw Error("Existing logout URL was customized; manual review required");
  return {...client,redirectUris:[to+"/"],webOrigins:[to],
    attributes:{...client.attributes,"post.logout.redirect.uris":to+"/"}};
}
export async function migrateExisting({apply=false,read=readFile,
  run=exec,remote=containerCommand,backup=backupPilot,
  verify=verifyBackup,checkDb=repairDbAuth}={}){
  const configPath=join(dir,".env.local"),realmPath=join(dir,".private","oagent-realm.json");
  const current=await read(configPath,"utf8");
  const oldOrigin=current.match(/^OAGENT_ORIGIN=(https:\/\/[^\r\n]+)$/m)?.[1];
  if(!oldOrigin||!/^https:\/\/[a-z0-9.-]+\.ts\.net$/i.test(oldOrigin))
    throw Error("Existing pilot origin is not the original private HTTPS host");
  const target=tailnetOrigin({OAGENT_SERVE_PORT:"8443"},run);
  if(oldOrigin!==tailnetOrigin({OAGENT_SERVE_PORT:"443"},run))
    throw Error("Current pilot origin does not belong to this Tailscale machine");
  const status=verifyPrivateServeAvailability(run("tailscale",
    ["serve","status","--json"]),8443);
  if(!status.existing)
    throw Error("Expected HTTPS 8443 to already forward to localhost:8787");
  if(!apply)return {status:"ready-to-migrate",target};
  const db=await checkDb();
  if(db.status!=="already-matched")
    throw Error("First run node repair-db-auth.mjs --apply to reconcile database roles.");
  const password=current.match(/^OAGENT_OWNER_PASSWORD=([a-f0-9]{48})$/m)?.[1];
  if(!password)throw Error("Missing saved owner credential");
  const template=JSON.parse(await read(join(dir,"oagent-realm.json"),"utf8"));
  const oldRealm=JSON.stringify(renderOwnerRealm(template,{origin:oldOrigin,password}),null,2)+"\n";
  if(await read(realmPath,"utf8")!==oldRealm)
    throw Error("Private Keycloak realm was modified; manual review required");
  const newRealm=JSON.stringify(renderOwnerRealm(template,{origin:target,password}),null,2)+"\n";
  const nonce=randomBytes(8).toString("hex");
  const authPath="/tmp/oagent-admin-"+nonce+".conf";
  const filePath="/tmp/oagent-client-"+nonce+".json";
  const cli="/opt/keycloak/bin/kcadm.sh";
  // Authentication uses the Keycloak container's preexisting bootstrap
  // credential through an environment variable, never a password CLI arg.
  const login='KC_CLI_PASSWORD="$KC_BOOTSTRAP_ADMIN_PASSWORD" exec '+
    cli+' config credentials --server http://127.0.0.1:8080/auth '+
    '--realm master --user admin --config '+authPath;
  let originalClient=null,updated=false;
  try{
    await remote(["sh","-c",login]);
    const clients=JSON.parse(await remote([cli,"get","clients","-r","oagent",
      "-q","clientId=oagent-web","--config",authPath]));
    if(!Array.isArray(clients)||clients.length!==1||
       !/^[0-9a-f-]{36}$/i.test(clients[0]?.id))
      throw Error("Expected exactly one OIDC web client");
    const clientId=clients[0].id;
    originalClient=JSON.parse(await remote([cli,"get","clients/"+clientId,
      "-r","oagent","--config",authPath]));
    const nextClient=planClientOrigin(originalClient,oldOrigin,target);
    // Authenticated, complete and VERIFIED encrypted backups first.
    const stamp=new Date().toISOString().replace(/[:.]/g,"-");
    const recovery=join(homedir(),".oagent-recovery-keys");
    await mkdir(recovery,{recursive:true,mode:0o700});
    const keyPath=join(recovery,"pilot-port-"+stamp+".key");
    const secret=randomBytes(40).toString("base64url");
    await writeFile(keyPath,secret+"\n",{flag:"wx",mode:0o600});
    const backupPath=join(dir,"backups","pre-existing-port-"+stamp);
    await backup({password:secret,output:backupPath});
    for(const name of ["oagent","keycloak"])
      await verify(join(backupPath,name+".oagent.enc"),secret);
    const localCopy=join(dir,".private","pre-existing-port-"+stamp);
    await mkdir(localCopy,{mode:0o700});
    await copyFile(configPath,join(localCopy,"env.local"));
    await copyFile(realmPath,join(localCopy,"realm.json"));
    await writeFile(join(localCopy,"keycloak-client.json"),
      JSON.stringify(originalClient,null,2)+"\n",{flag:"wx",mode:0o600});
    await remote(["sh","-c","umask 077; cat > "+filePath],JSON.stringify(nextClient));
    await remote([cli,"update","clients/"+clientId,"-r","oagent",
      "-f",filePath,"--config",authPath]);
    updated=true;
    const checked=JSON.parse(await remote([cli,"get","clients/"+clientId,
      "-r","oagent","--config",authPath]));
    if(JSON.stringify(checked.redirectUris)!==JSON.stringify(nextClient.redirectUris)||
       JSON.stringify(checked.webOrigins)!==JSON.stringify(nextClient.webOrigins)||
       checked.attributes?.["post.logout.redirect.uris"]!==target+"/")
      throw Error("Keycloak did not save the new OIDC redirect");
    let nextEnv=current.replace("OAGENT_ORIGIN="+oldOrigin+"\n",
      "OAGENT_ORIGIN="+target+"\n");
    if(nextEnv===current)throw Error("Saved pilot origin could not be updated");
    if(/^OAGENT_SERVE_PORT=/m.test(nextEnv))
      nextEnv=nextEnv.replace(/^OAGENT_SERVE_PORT=.*$/m,"OAGENT_SERVE_PORT=8443");
    else nextEnv=nextEnv.trimEnd()+"\nOAGENT_SERVE_PORT=8443\n";
    const tmpEnv=join(dir,".env.local."+nonce+".tmp");
    const tmpRealm=join(dir,".private","realm."+nonce+".tmp");
    await writeFile(tmpEnv,nextEnv,{flag:"wx",mode:0o600});
    await writeFile(tmpRealm,newRealm,{flag:"wx",mode:0o600});
    await rename(tmpEnv,configPath);
    await rename(tmpRealm,realmPath);
    return {status:"migrated",target,backupPath,keyPath,localCopy};
  }catch(error){
    // A failed local file update must not leave the OIDC client half-migrated.
    if(updated&&originalClient){
      try{
        await remote(["sh","-c","umask 077; cat > "+filePath],
          JSON.stringify(originalClient));
        await remote([cli,"update","clients/"+originalClient.id,"-r","oagent",
          "-f",filePath,"--config",authPath]);
      }catch{/* Original client was saved in a private backup. */}
    }
    throw error;
  }finally{
    try{await remote(["sh","-c","rm -f "+authPath+" "+filePath]);}catch{}
  }
}
async function main(){
  const args=process.argv.slice(2);
  if(args[0]!=="8443"||args.length>2||(args[1]&&args[1]!=="--apply"))
    throw Error("Usage: node migrate-existing-port.mjs 8443 [--apply]");
  const r=await migrateExisting({apply:args.includes("--apply")});
  if(r.status==="ready-to-migrate"){
    console.log("[READY] Existing HTTPS 8443 -> 8787 route verified.");
    console.log("Run node migrate-existing-port.mjs 8443 --apply after database repair.");
  }else{
    console.log("[PASS] OIDC client and pilot configuration now use "+r.target);
    console.log("Encrypted database backups: "+r.backupPath);
    console.log("Separate recovery key: "+r.keyPath);
    console.log("Private configuration backups: "+r.localCopy);
    console.log("No Docker volume or Tailscale route was deleted or reset.");
    console.log("Now restart with START-O-AGENT.cmd.");
  }
}
if(process.argv[1]&&fileURLToPath(import.meta.url)===process.argv[1])
  main().catch(()=>{console.error(
    "[FIX] Existing-port migration stopped. Check Keycloak admin login, " +
    "database role passwords and private backups. Tailscale routes and volumes were preserved.");
    process.exitCode=1;});
