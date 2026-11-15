import {spawn} from "node:child_process";
import {realpath} from "node:fs/promises";
import {isAbsolute,relative,resolve,sep} from "node:path";
import {codexChildEnv} from "./codex-env.mjs";

// Read-only Codex app-server methods: never resume, inject, steer, or start.
const SESSION_ID=/^[A-Za-z0-9_-]{8,120}$/;
const MAX_BYTES=5*1024*1024;
const sane=(v,n)=>typeof v==="string"?v.replace(/[\x00-\x08\x0b\x0c\x0e-\x1f]/g,"").slice(0,n):"";
export function projectContains(root,folder) {
  if(typeof folder!=="string"||!isAbsolute(folder))return false;
  const r=resolve(root),f=resolve(folder);
  const diff=relative(r,f);
  return diff!== ".." && !diff.startsWith(".."+sep) && !isAbsolute(diff);
}
export async function safeCodexThreads(threads,root,{realpathImpl=realpath,max=12}={}) {
  const canonical=await realpathImpl(root);
  const result=[];
  for(const thread of Array.isArray(threads)?threads.slice(0,60):[]){
    if(result.length>=max)break;
    if(!SESSION_ID.test(thread?.id||"") ||
       typeof thread.cwd!=="string"||thread.cwd.length>600 ||
       !projectContains(canonical,thread.cwd))continue;
    let actual;
    try{actual=await realpathImpl(thread.cwd);}catch{continue;}
    if(!projectContains(canonical,actual))continue;
    const timestamp=Number(thread.updatedAt);
    result.push({
      sessionId:thread.id,cwd:actual,
      title:sane(thread.name,100)||sane(thread.preview,100)||"Codex session",
      preview:sane(thread.preview,240),
      sourceKind:["cli","vscode"].includes(thread.source?.kind)?
        thread.source.kind:"unknown",
      updatedAt:Number.isFinite(timestamp)&&timestamp>0
        ?new Date(timestamp*1000).toISOString():new Date(0).toISOString(),
      messages:[],
    });
  }
  return result;
}
export function boundedCodexMessages(thread,{maxMessages=20}={}) {
  const turns=Array.isArray(thread?.turns)?thread.turns.slice(-20):[];
  const result=[];
  for(const turn of turns){
    for(const item of Array.isArray(turn?.items)?turn.items:[]){
      const role=item?.type==="userMessage"?"user":
        item?.type==="agentMessage"?"assistant":null;
      if(!role)continue;
      const input=role==="user"?item.content:item.text;
      const output=typeof input==="string"?input:
        Array.isArray(input)?input.filter(x=>x?.type==="text")
          .map(x=>x?.text||"").join("\n"):"";
      const value=sane(output,1400);
      if(value.trim())result.push({role,text:value});
    }
  }
  return result.slice(-maxMessages);
}
/**
 * A disposable local app-server lists persisted threads (CLI and VS Code)
 * and reads bounded stored history. This cannot attach to an existing IDE's
 * running turn or intercept another process's approval channel.
 */
export async function discoverStoredCodexSessions({
  root,env=process.env,spawnImpl=spawn,realpathImpl=realpath,
  isWindows=process.platform==="win32",timeoutMs=11000,
}={}){
  if(!root||!isAbsolute(root))throw Error("Verified Codex workspace required");
  const canonical=await realpathImpl(root);
  const command=isWindows?"powershell.exe":"codex";
  const args=isWindows?
    ["-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass",
      "-Command","& codex app-server"]:["app-server"];
  return new Promise((resolvePromise,rejectPromise)=>{
    let child,finished=false,bytes=0,buffer="",rows=[],nextId=3;
    let pending=0;
    const timeout=setTimeout(()=>finish(Error("Local Codex discovery unavailable")),timeoutMs);
    function finish(error){
      if(finished)return;
      finished=true;
      clearTimeout(timeout);
      try{child?.stdin.end();}catch{}
      try{child?.kill();}catch{}
      if(error)rejectPromise(error);
      else resolvePromise(rows);
    }
    function send(id,method,params){
      if(!finished)child.stdin.write(JSON.stringify({id,method,params})+"\n");
    }
    async function accept(message){
      if(finished||!message||typeof message!=="object")return;
      if(message.id===1){
        if(message.error)return finish(Error("Codex handshake was rejected"));
        child.stdin.write(JSON.stringify({method:"initialized",params:{}})+"\n");
        send(2,"thread/list",{limit:30,sortKey:"updated_at",
          sortDirection:"desc",sourceKinds:["cli","vscode"]});
      }else if(message.id===2){
        if(message.error)return finish(Error("Codex thread listing unavailable"));
        try{
          rows=await safeCodexThreads(message.result?.data,canonical,
            {realpathImpl,max:10});
        }catch{return finish(Error("Could not verify local session paths"));}
        pending=Math.min(rows.length,6);
        if(!pending)return finish();
        // Newest six only; no unbounded history or secret-file scanning.
        rows.slice(0,pending).forEach((row,index)=>
          send(nextId+index,"thread/read",{
            threadId:row.sessionId,includeTurns:true,
          }));
      }else if(message.id>=3&&message.id<9){
        const index=message.id-3;
        if(rows[index]&&!message.error){
          rows[index].messages=boundedCodexMessages(message.result?.thread);
        }
        pending--;
        if(pending===0)finish();
      }
    }
    try{
      child=spawnImpl(command,args,{cwd:canonical,
        env:codexChildEnv(env),stdio:["pipe","pipe","pipe"],windowsHide:true});
    }catch{return finish(Error("Codex CLI is not installed"));}
    child.on("error",()=>finish(Error("Codex CLI is not installed")));
    child.on("exit",()=>{if(!finished)finish(Error("Codex discovery process exited"));});
    child.stderr.on("data",()=>{}); // Never print private Codex logs.
    child.stdout.on("data",chunk=>{
      if(finished)return;
      bytes+=chunk.length;
      if(bytes>MAX_BYTES)return finish(Error("Codex metadata exceeded safe limit"));
      buffer+=chunk.toString("utf8");
      if(buffer.length>MAX_BYTES)return finish(Error("Codex response exceeded limit"));
      let pos;
      while(!finished && (pos=buffer.indexOf("\n"))>=0){
        const line=buffer.slice(0,pos).trim();buffer=buffer.slice(pos+1);
        if(!line)continue;
        if(line.length>1024*1024)return finish(Error("Oversized Codex message"));
        try{void accept(JSON.parse(line));}catch{/* Skip provider noise. */}
      }
    });
    send(1,"initialize",{clientInfo:{name:"o_agent",
      title:"O-AGENT stored session browser",version:"0.13.1"},
      capabilities:{experimentalApi:true}});
  });
}
