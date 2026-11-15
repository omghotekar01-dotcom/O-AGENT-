import {execFileSync} from "node:child_process";
import {readFile,writeFile,mkdir,copyFile,chmod,rename} from "node:fs/promises";
import {dirname,join} from "node:path";
import {fileURLToPath} from "node:url";
import {renderOwnerRealm,tailnetOrigin} from "./setup.mjs";
import {verifyPrivateServeAvailability} from "./start.mjs";

const dir=dirname(fileURLToPath(import.meta.url));
// Stages deliberately contain no credentials, tokens, hostnames or subprocess output.
export const migrationRemedies=Object.freeze({
  "read saved settings":"Confirm .env.local exists; do not delete or post it.",
  "verify old private origin":"Check this Windows computer is signed into the original Tailscale tailnet.",
  "check Docker Desktop":"Start Docker Desktop and verify docker info reports a Server section.",
  "check existing O-AGENT data":"If this pilot has existing containers or volumes, do not delete them. Manual identity migration is required.",
  "check Tailscale port 8443":"Run tailscale serve status; another route may already use 8443. Do not reset it.",
  "verify private login settings":"The saved Keycloak realm or credentials differ. Preserve the files and investigate.",
  "back up private settings":"Check OneDrive/file permissions and available disk space. Do not delete the original files.",
  "update private settings":"A file is locked or cannot be replaced; preserve .private backup copies and inspect the saved origin locally."
});
let stage="read saved settings";
async function main(){
  if(process.argv[2]!=="8443")throw Error("Usage: node migrate-port.mjs 8443");
  const run=(cmd,args)=>execFileSync(cmd,args,{encoding:"utf8",timeout:10000,
    stdio:["ignore","pipe","pipe"]});
  const envPath=join(dir,".env.local"),realmPath=join(dir,".private","oagent-realm.json");
  const secrets=await readFile(envPath,"utf8");
  const from=secrets.match(/^OAGENT_ORIGIN=(https:\/\/[^\r\n]+)$/m)?.[1];
  if(!from)throw Error("Existing origin missing");
  stage="verify old private origin";
  if(new URL(from).port==="8443"){
    console.log("Already using 8443; nothing changed.");return;
  }
  if(from!==tailnetOrigin({OAGENT_SERVE_PORT:"443"},run))
    throw Error("Current 443 origin does not belong to this device");
  const to=tailnetOrigin({OAGENT_SERVE_PORT:"8443"},run);
  stage="check Docker Desktop";
  // Docker engine must be available; do not treat connection failure as empty state.
  run("docker",["info","--format","{{.ServerVersion}}"]);
  stage="check existing O-AGENT data";
  const volumes=run("docker",["volume","ls","-q","--filter",
    "label=com.docker.compose.project=oagent-free-pilot"]).trim();
  const containers=run("docker",["ps","-a","--format","{{.Names}}",
    "--filter","label=com.docker.compose.project=oagent-free-pilot"]).trim();
  if(volumes||containers)throw Error("Pilot data exists; no changes were made");
  stage="check Tailscale port 8443";
  verifyPrivateServeAvailability(run("tailscale",["serve","status","--json"]),8443);
  stage="verify private login settings";
  const password=secrets.match(/^OAGENT_OWNER_PASSWORD=([a-f0-9]{48})$/m)?.[1];
  if(!password)throw Error("Unexpected credentials");
  const template=JSON.parse(await readFile(join(dir,"oagent-realm.json"),"utf8"));
  const savedRealm=await readFile(realmPath,"utf8");
  const oldRealm=JSON.stringify(renderOwnerRealm(template,{origin:from,password}),null,2)+"\n";
  if(savedRealm!==oldRealm)throw Error("Custom private realm: no changes made");
  const nextRealm=JSON.stringify(renderOwnerRealm(template,{origin:to,password}),null,2)+"\n";
  const nextEnv=secrets.replace("OAGENT_ORIGIN="+from+"\n","OAGENT_ORIGIN="+to+"\n");
  if(nextEnv===secrets)throw Error("Origin migration failed");
  stage="back up private settings";
  const backup=join(dir,".private","pre-8443-backup-"+Date.now());
  await mkdir(backup,{mode:0o700});
  const envCopy=join(backup,"env.local"),realmCopy=join(backup,"realm.json");
  await copyFile(envPath,envCopy);await chmod(envCopy,0o600);
  await copyFile(realmPath,realmCopy);await chmod(realmCopy,0o600);
  stage="update private settings";
  const tmpEnv=join(dir,".env.local.8443.tmp");
  const tmpRealm=join(dir,".private","oagent-realm.8443.tmp");
  await writeFile(tmpEnv,nextEnv,{flag:"wx",mode:0o600});
  await writeFile(tmpRealm,nextRealm,{flag:"wx",mode:0o600});
  await rename(tmpEnv,envPath);
  await rename(tmpRealm,realmPath);
  console.log("Origin migrated to "+to+"; existing passwords preserved.");
  console.log("Private backups saved in .private. Run START-O-AGENT.cmd again.");
}
if(process.argv[1]&&fileURLToPath(import.meta.url)===process.argv[1])
  main().catch(()=>{
    console.error("[FIX] Port migration stopped during: "+stage);
    console.error(migrationRemedies[stage]||"Keep private backups and inspect your installation.");
    console.error("No Tailscale Serve reset or Docker volume deletion was performed.");
    process.exitCode=1;});
