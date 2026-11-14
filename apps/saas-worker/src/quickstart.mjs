import {readFile,realpath,stat} from "node:fs/promises";
import {hostname} from "node:os";
import {dirname,join,resolve,isAbsolute} from "node:path";
import {fileURLToPath} from "node:url";
import {enrollCloudWorker,readIdentity} from "./enroll.mjs";
import {SignedCloudWorker} from "./worker.mjs";

const here=dirname(fileURLToPath(import.meta.url));
const pilotConfig=join(here,"../../../deploy/saas/free-pilot/.env.local");
export async function getPilotOrigin(env=process.env){
  if(env.OAGENT_SAAS_ORIGIN)return env.OAGENT_SAAS_ORIGIN;
  let content;
  try{content=await readFile(pilotConfig,"utf8");}
  catch{throw Error("No local free pilot was set up. First run node deploy/saas/free-pilot/setup.mjs");}
  const match=content.match(/^OAGENT_ORIGIN=(https:\/\/[^\r\n]+)$/m);
  if(!match)throw Error("Local free pilot has no valid HTTPS origin");
  return match[1];
}
export async function main({argv=process.argv,env=process.env}={}){
  const input=argv[2]||env.OAGENT_WORKSPACE_ROOT;
  if(!input||!isAbsolute(resolve(input)))
    throw Error("Give the workspace path: node apps/saas-worker/src/quickstart.mjs /absolute/workspace/path");
  const workspace=await realpath(resolve(input));
  if(!(await stat(workspace)).isDirectory())
    throw Error("Workspace must be an existing directory");
  const origin=await getPilotOrigin(env);
  console.log("O-AGENT private workspace: "+workspace);
  console.log("Only your enrolled project and explicitly approved turns will run.");
  await enrollCloudWorker({origin,name:"O-AGENT on "+hostname()});
  const identity=await readIdentity();
  if(!identity?.deviceId||!identity?.privateKeyPem)
    throw Error("Device was not enrolled. Approve the pairing link on your phone.");
  console.log("Encrypted HTTPS connection to private SaaS: "+origin);
  console.log("Worker started. Keep this computer awake for remote control.");
  console.log("Provider features start disabled until you opt in and authenticate.");
  await new SignedCloudWorker({
    origin,deviceId:identity.deviceId,privateKeyPem:identity.privateKeyPem,
    root:workspace,env,
  }).start();
}
if(process.argv[1]&&fileURLToPath(import.meta.url)===resolve(process.argv[1]))
  await main();
