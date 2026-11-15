import {execFileSync} from "node:child_process";
import {readFile,writeFile,mkdir,copyFile,chmod,rename} from "node:fs/promises";
import {dirname,join} from "node:path";
import {fileURLToPath} from "node:url";
import {renderOwnerRealm,tailnetOrigin} from "./setup.mjs";
import {verifyPrivateServeAvailability} from "./start.mjs";

const dir=dirname(fileURLToPath(import.meta.url));
async function main(){
  if(process.argv[2]!=="8443")throw Error("Usage: node migrate-port.mjs 8443");
  const run=(cmd,args)=>execFileSync(cmd,args,{encoding:"utf8",timeout:10000,
    stdio:["ignore","pipe","pipe"]});
  const envPath=join(dir,".env.local"),realmPath=join(dir,".private","oagent-realm.json");
  const secrets=await readFile(envPath,"utf8");
  const from=secrets.match(/^OAGENT_ORIGIN=(https:\/\/[^\r\n]+)$/m)?.[1];
  if(!from)throw Error("Existing origin missing");
  if(new URL(from).port==="8443"){
    console.log("Already using 8443; nothing changed.");return;
  }
  if(from!==tailnetOrigin({OAGENT_SERVE_PORT:"443"},run))
    throw Error("Current 443 origin does not belong to this device");
  const to=tailnetOrigin({OAGENT_SERVE_PORT:"8443"},run);
  // Docker engine must be available; do not treat connection failure as empty state.
  run("docker",["info","--format","{{.ServerVersion}}"]);
  const volumes=run("docker",["volume","ls","-q","--filter",
    "label=com.docker.compose.project=oagent-free-pilot"]).trim();
  const containers=run("docker",["ps","-a","--format","{{.Names}}",
    "--filter","label=com.docker.compose.project=oagent-free-pilot"]).trim();
  if(volumes||containers)throw Error("Pilot data exists; no changes were made");
  verifyPrivateServeAvailability(run("tailscale",["serve","status","--json"]),8443);
  const password=secrets.match(/^OAGENT_OWNER_PASSWORD=([a-f0-9]{48})$/m)?.[1];
  if(!password)throw Error("Unexpected credentials");
  const template=JSON.parse(await readFile(join(dir,"oagent-realm.json"),"utf8"));
  const savedRealm=await readFile(realmPath,"utf8");
  const oldRealm=JSON.stringify(renderOwnerRealm(template,{origin:from,password}),null,2)+"\n";
  if(savedRealm!==oldRealm)throw Error("Custom private realm: no changes made");
  const nextRealm=JSON.stringify(renderOwnerRealm(template,{origin:to,password}),null,2)+"\n";
  const nextEnv=secrets.replace("OAGENT_ORIGIN="+from+"\n","OAGENT_ORIGIN="+to+"\n");
  if(nextEnv===secrets)throw Error("Origin migration failed");
  const backup=join(dir,".private","pre-8443-backup-"+Date.now());
  await mkdir(backup,{mode:0o700});
  const envCopy=join(backup,"env.local"),realmCopy=join(backup,"realm.json");
  await copyFile(envPath,envCopy);await chmod(envCopy,0o600);
  await copyFile(realmPath,realmCopy);await chmod(realmCopy,0o600);
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
  main().catch(()=>{console.error(
    "Migration refused or failed; verify Docker/Tailscale and preserve private backups.");
    process.exitCode=1;});
