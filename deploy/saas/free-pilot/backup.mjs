import {spawn} from "node:child_process";
import {mkdir,rename,rm,writeFile} from "node:fs/promises";
import {dirname,join,resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {encryptBackup} from "./backup-crypto.mjs";
const directory=dirname(fileURLToPath(import.meta.url));
const argumentsFor=cmd=>["compose","--env-file",".env.local",
  "-f","compose.yaml","exec","-T","db",...cmd];
export async function backupPilot({
  output=join(directory,"backups",new Date().toISOString().replace(/[:.]/g,"-")),
  password=process.env.OAGENT_BACKUP_PASSPHRASE,spawnImpl=spawn,
}={}){
  if(!password||password.length<20)
    throw Error("Set OAGENT_BACKUP_PASSPHRASE (20+ characters) before backup");
  const destination=resolve(output);
  if(destination===directory||destination.startsWith(join(directory,".env")))
    throw Error("Invalid backup destination");
  await mkdir(destination,{recursive:true,mode:0o700});
  const names=["oagent","keycloak"],written=[];
  try{
    for(const database of names){
      const target=join(destination,database+".oagent.enc");
      const child=spawnImpl("docker",argumentsFor([
        "pg_dump","-Fc","--no-comments","-U","postgres","-d",database,
      ]),{cwd:directory,stdio:["ignore","pipe","pipe"]});
      child.stderr.resume(); // never print private SQL or connection metadata
      const exit=new Promise((done,reject)=>{
        child.once("error",reject);
        child.once("close",code=>code===0?done():reject(
          Error("Docker pg_dump failed for "+database+" (exit "+code+")")));
      });
      try{
        await encryptBackup(child.stdout,target,password);
        await exit;
      }catch(error){
        child.kill("SIGTERM");
        await rm(target,{force:true});
        throw error;
      }
      written.push(target);
    }
    await writeFile(join(destination,"README.txt"),
      "O-AGENT local encrypted backup. Contains private identities, user data and approvals.\n"+
      "Restore only with restore.mjs in a disposable pilot after verifying both files.\n",
      {mode:0o600,flag:"wx"});
    console.log("Two encrypted database backups created at: "+destination);
    return destination;
  }catch(error){
    for(const path of written)await rm(path,{force:true});
    throw error;
  }
}
if(process.argv[1]&&fileURLToPath(import.meta.url)===resolve(process.argv[1]))
  await backupPilot({output:process.argv[2]});
