import {spawn} from "node:child_process";
import {access} from "node:fs/promises";
import {dirname,join,resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {decryptBackup,verifyBackup} from "./backup-crypto.mjs";
const dir=dirname(fileURLToPath(import.meta.url));
const compose=args=>["compose","--env-file",".env.local","-f","compose.yaml",...args];
async function docker(args,{input,spawnImpl=spawn}={}){
  const child=spawnImpl("docker",compose(args),
    {cwd:dir,stdio:[input?"pipe":"ignore","pipe","pipe"]});
  child.stdout.resume();child.stderr.resume();
  const ended=new Promise((ok,fail)=>{
    child.once("error",fail);
    child.once("close",code=>code===0?ok():fail(Error(
      "Docker restore command failed (exit "+code+")")));
  });
  if(input)await decryptBackup(input,process.env.OAGENT_BACKUP_PASSPHRASE,
    child.stdin);
  await ended;
}
export async function restorePilot(folder){
  if(process.env.OAGENT_RESTORE_CONFIRM!=="I_ACCEPT_DESTRUCTIVE_PILOT_RESTORE")
    throw Error("Refusing destructive restore without explicit confirmation");
  const path=resolve(folder||"");
  const files=["oagent","keycloak"].map(name=>join(path,name+".oagent.enc"));
  for(const file of files)await access(file);
  // Two full authentication checks BEFORE the first destructive DB operation.
  for(const file of files)
    await verifyBackup(file,process.env.OAGENT_BACKUP_PASSPHRASE);
  await docker(["stop","api","identity","gateway"]);
  try{
    for(let i=0;i<files.length;i++){
      await docker(["exec","-T","db","pg_restore","--clean","--if-exists",
        "--exit-on-error","-U","postgres","-d",["oagent","keycloak"][i]],
        {input:files[i]});
    }
    console.log("Backup restored. Restart with: docker compose --env-file .env.local -f compose.yaml up -d");
  }catch(error){
    console.error("Restore did not complete; services remain stopped for safe recovery");
    throw error;
  }
}
if(process.argv[1]&&fileURLToPath(import.meta.url)===resolve(process.argv[1]))
  await restorePilot(process.argv[2]);
