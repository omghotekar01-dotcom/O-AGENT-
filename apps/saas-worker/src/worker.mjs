import {readFile, readdir,lstat,realpath} from "node:fs/promises";
import {basename,join,isAbsolute,relative,resolve,sep} from "node:path";
import {pathToFileURL} from "node:url";
import {randomUUID} from "node:crypto";
import {deviceHeaders} from "../../saas/src/device-crypto.mjs";
import {runProviderTurn} from "../../gateway/src/provider-turn.mjs";
import {runCodexTurn} from "../../gateway/src/codex-turn.mjs";

const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const fail=message=>Object.assign(Error(message),{safe:true});
function safeUrl(origin) {
  const url=new URL(origin);
  if(url.protocol!=="https:" || url.pathname!=="/" || url.username || url.password)
    throw Error("Cloud worker requires a public HTTPS SaaS control-plane origin");
  return url.origin;
}
function allowedPath(root,folder){
  const rel=relative(root,folder);
  return !rel.startsWith(".."+sep)&&rel!==".."&&!isAbsolute(rel);
}
async function inventory(root){
  const children=(await readdir(root)).slice(0,100);
  const entries=[];
  for(const name of children){
    const stat=await lstat(join(root,name));
    entries.push({name:basename(name),
      type:stat.isSymbolicLink()?"symlink":
        stat.isDirectory()?"directory":stat.isFile()?"file":"other"});
  }
  return {root,entries};
}
function supported(env) {
  return ["workspace_inventory",
    ...(env.OAGENT_ENABLE_CLAUDE_AGENT_SDK==="1"?["claude_agent_turn"]:[]),
    ...(env.OAGENT_ENABLE_COPILOT_SDK==="1"?["copilot_sdk_turn"]:[]),
    ...(env.OAGENT_ENABLE_CODEX_LOCAL_SYNC==="1"?["codex_cli_turn"]:[]),
  ];
}
/** Dedicated one-tenant worker; never share its filesystem or provider login
 * with other customers. Every request is signed and backed by a durable nonce.
 */
export class SignedCloudWorker {
  constructor({origin,deviceId,privateKeyPem,root,env=process.env,
    fetchImpl=fetch,providerRunner=runProviderTurn,codexRunner=runCodexTurn,
    now=()=>Date.now(),wait=sleep,renewIntervalMs=30000}){
    this.origin=safeUrl(origin);
    this.deviceId=deviceId;this.privateKeyPem=privateKeyPem;
    this.root=resolve(root);this.env={...env,OAGENT_WORKSPACE_ROOT:this.root};
    this.fetchImpl=fetchImpl;this.providerRunner=providerRunner;
    this.codexRunner=codexRunner;this.now=now;this.wait=wait;
    this.renewIntervalMs=renewIntervalMs;this.revoked=false;
  }
  async api(path,{body={},method="POST"}={}){
    const raw=method==="GET"?Buffer.alloc(0):Buffer.from(JSON.stringify(body),"utf8");
    const proof=deviceHeaders(this.privateKeyPem,{
      deviceId:this.deviceId,method,path,rawBody:raw,now:this.now,
    });
    const response=await this.fetchImpl(this.origin+path,{
      method,headers:{...proof,accept:"application/json",
        ...(method==="POST"?{"content-type":"application/json"}:{})},
      ...(method==="POST"?{body:raw}:{}),
      signal:AbortSignal.timeout(15000),
    });
    const result=await response.json().catch(()=>({}));
    if(!response.ok){
      if(response.status===401||response.status===403){
        this.revoked=true;
        throw fail("Device authorization revoked. Re-enroll from the owner account.");
      }
      throw fail("O-AGENT signed worker request failed (HTTP "+response.status+")");
    }
    return result;
  }
  async initialize(){
    await realpath(this.root);
    await this.api("/v1/device/capabilities",
      {body:{capabilities:supported(this.env)}});
  }
  async execute(run){
    if(!run?.id||!run.leaseToken)throw fail("Missing server-issued run lease");
    const lease=run.leaseToken;
    let lost=false;
    const abort=new AbortController();
    // One lease-renewal failure shuts down execution rather than risking an
    // unauthorized prolonged turn. Expiry never auto-requeues side effects.
    let renewing=false;
    const renewal=setInterval(async()=>{
      if(renewing||lost)return;
      renewing=true;
      try{
        await this.api("/v1/device/runs/"+run.id+"/renew",
          {body:{leaseToken:lease}});
      }catch{
        lost=true;abort.abort();
      }finally{renewing=false;}
    },this.renewIntervalMs);
    let completed=false;
    try{
      const root=await realpath(this.root);
      let result;
      if(run.kind==="workspace_inventory"){
        result=await inventory(root);
      }else{
        if(typeof run.cwd!=="string" || !isAbsolute(run.cwd))
          throw fail("Server-approved workspace is not absolute");
        const actual=await realpath(run.cwd);
        if(!allowedPath(root,actual) ||
           resolve(actual).toLowerCase()!==resolve(run.cwd).toLowerCase())
          throw fail("Workspace outside enrolled isolated worker root");
        const task={id:run.id,kind:run.kind,
          parameters:{cwd:actual,mode:run.mode,
            prompt:run.prompt,sessionId:run.session_id??null}};
        const callbacks={
          env:this.env,signal:abort.signal,
          sendUpdate:async event=>{
            if(lost)throw fail("Run lease lost");
            await this.api("/v1/device/runs/"+run.id+"/events",
              {body:{leaseToken:lease,kind:event.type,text:event.text||""}});
          },
          askPermission:async request=>{
            if(lost || abort.signal.aborted)return false;
            const entry=await this.api("/v1/device/runs/"+run.id+"/approvals",
              {body:{leaseToken:lease,requestId:request.id,
                description:request.description}});
            const until=this.now()+180000;
            while(this.now()<until && !lost && !abort.signal.aborted){
              await this.wait(1800);
              const status=await this.api("/v1/device/approvals/"+
                entry.approvalId,{method:"GET"});
              if(status.state==="approved")return true;
              if(["denied","expired"].includes(status.state))return false;
            }
            return false;
          },
        };
        if(["claude_agent_turn","copilot_sdk_turn"].includes(run.kind)){
          result=await this.providerRunner(task,{
            ...callbacks,importSdk:specifier=>import(specifier),
          });
        }else if(run.kind==="codex_cli_turn"){
          result=await this.codexRunner(task,callbacks);
        }else throw fail("Worker cannot execute this task kind");
        if(result?.providerStatus!=="completed")
          throw fail("Provider did not confirm completion");
      }
      if(lost || abort.signal.aborted)throw fail("Run authorization expired");
      await this.api("/v1/device/runs/"+run.id+"/complete",
        {body:{leaseToken:lease,ok:true,result}});
      completed=true;
      return {completed:true};
    }catch(error){
      // A lost lease may have been revoked; no result may be persisted,
      // and the server will move it to needs_recovery (never duplicate).
      if(!lost){
        try{await this.api("/v1/device/runs/"+run.id+"/complete",
          {body:{leaseToken:lease,ok:false,
            error:error.safe?error.message:"Provider turn failed; inspect the worker locally"}});}
        catch{}
      }
      return {completed:false,error:error.safe?error.message:
        "Provider execution failed"};
    }finally{clearInterval(renewal);}
  }
  async tick(){
    if(this.revoked)throw fail("Device identity revoked");
    await this.api("/v1/device/heartbeat");
    const {run}=await this.api("/v1/device/claim");
    if(!run)return {claimed:false};
    const result=await this.execute(run);
    return {claimed:true,...result};
  }
  async start(){
    await this.initialize();
    while(!this.revoked){
      try{await this.tick();}catch(error){
        if(this.revoked)throw error;
        console.error("O-AGENT worker temporarily disconnected; retrying securely");
      }
      await this.wait(3500);
    }
  }
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
  const env=process.env;
  const file=env.OAGENT_DEVICE_PRIVATE_KEY_FILE;
  if(!file || !env.OAGENT_DEVICE_ID || !env.OAGENT_WORKSPACE_ROOT)
    throw Error("Set OAGENT_DEVICE_PRIVATE_KEY_FILE, OAGENT_DEVICE_ID and OAGENT_WORKSPACE_ROOT");
  const privateKeyPem=await readFile(file,"utf8");
  const worker=new SignedCloudWorker({
    origin:env.OAGENT_SAAS_ORIGIN,deviceId:env.OAGENT_DEVICE_ID,
    privateKeyPem,root:env.OAGENT_WORKSPACE_ROOT,
  });
  await worker.start();
}
