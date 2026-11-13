import { spawn } from "node:child_process";
import { explainCodexError } from "./codex-errors.mjs";
import { codexChildEnv } from "./codex-env.mjs";

const MAX_OUTPUT = 4 * 1024 * 1024;
const MAX_MESSAGES = 32;
const MAX_TEXT = 13000;
const MAX_TURNS = 20;
const LIMIT_PER_MESSAGE = 2100;

function cleanText(value, limit = LIMIT_PER_MESSAGE) {
  if (typeof value !== "string") return "";
  return value.replace(/\u0000/g, "").slice(0, limit);
}
/** Explicitly allowlisted user and assistant text; never raw tool arguments,
 * raw tool results, reasoning, hidden model content or access tokens. */
export function conversationMessages(thread) {
  const turns = Array.isArray(thread?.turns) ? thread.turns.slice(-MAX_TURNS) : [];
  const messages = [];
  for (const turn of turns) {
    if (!Array.isArray(turn?.items)) continue;
    for (const item of turn.items) {
      if (!item || typeof item !== "object") continue;
      if (item.type === "userMessage") {
        const parts = Array.isArray(item.content) ? item.content : [];
        const text = cleanText(parts.filter(p => p?.type === "text" &&
          typeof p.text === "string").map(p => p.text).join("\n"));
        if (text.trim()) messages.push({ role:"user", text });
      } else if (item.type === "agentMessage" || item.type === "plan") {
        const text = cleanText(item.text);
        if (text.trim()) messages.push({ role:"assistant", text });
      }
    }
  }
  // Bounded owner-only display/cache: newest messages first, then restore
  // chronology. Do not silently send raw rollout files to the phone.
  const selected = [];
  let used = 0;
  for (const message of messages.slice(-MAX_MESSAGES).reverse()) {
    const remaining = MAX_TEXT - used;
    if (remaining <= 0) break;
    const text = message.text.slice(0, remaining);
    selected.push({role:message.role,text});
    used += text.length;
  }
  return {
    messages:selected.reverse(),
    truncated: messages.length > selected.length ||
      selected.some(x => x.text.length < 1) || turns.length >= MAX_TURNS,
  };
}

/**
 * One short-lived, READ-ONLY request to Codex thread/read. It never resumes a
 * thread, starts a turn or attaches to another IDE tab. Reads only explicit
 * allowlisted text from a user-selected previously discovered thread.
 */
export async function readCodexHistory(task, {
  spawnImpl = spawn, env = process.env,
  isWindows = process.platform === "win32", timeoutMs = 20000,
} = {}) {
  if (task?.kind !== "codex_cli_history") throw Error("Expected selected Codex conversation");
  const sessionId = task.parameters?.sessionId;
  if (typeof sessionId !== "string" || !/^[a-zA-Z0-9_-]{8,120}$/.test(sessionId))
    throw Error("Invalid selected Codex conversation");
  const executable = isWindows ? "powershell.exe" : "codex";
  const args = isWindows
    ? ["-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-Command","& codex app-server"]
    : ["app-server"];
  const childEnv = codexChildEnv(env);
  return await new Promise((resolve, reject) => {
    let child;
    try {
      child = spawnImpl(executable,args,{
        stdio:["pipe","pipe","pipe"], env:childEnv,windowsHide:true,
      });
    } catch {
      reject(Error("CODEX_NOT_INSTALLED: The laptop cannot launch the Codex CLI. Install/sign in to Codex and restart the worker."));
      return;
    }
    let done=false, stage=0, total=0, buffer="";
    const timer=setTimeout(()=>finish(Error("CODEX_READ_TIMEOUT: Codex did not return saved conversation messages. Check whether the laptop CLI is responding.")),timeoutMs);
    function finish(error,result) {
      if(done)return;
      done=true;
      clearTimeout(timer);
      try{child.stdin.end();}catch{}
      try{child.kill();}catch{}
      if(error) reject(error); else resolve(result);
    }
    const send=(v)=>{if(!done)child.stdin.write(JSON.stringify(v)+"\n");};
    function handle(msg) {
      if (!msg || typeof msg !== "object")return;
      if (msg.id===1 && stage===0) {
        if(msg.error)return finish(Error(explainCodexError(msg.error,"initialization")));
        stage=1;
        send({method:"initialized",params:{}});
        send({id:2,method:"thread/read",params:{threadId:sessionId,includeTurns:true}});
      } else if(msg.id===2 && stage===1) {
        if(msg.error)return finish(Error(explainCodexError(msg.error,"read")));
        const thread=msg.result?.thread;
        if(!thread || thread.id !== sessionId)
          return finish(Error("CODEX_INVALID_HISTORY: Codex returned a different conversation. No data was accepted."));
        const formatted=conversationMessages(thread);
        finish(null,{
          provider:"codex_cli",sessionId,
          messages:formatted.messages,truncated:formatted.truncated,
          totalShown:formatted.messages.length,
          observedStatus: typeof thread.status?.type === "string"
            ? thread.status.type.slice(0,40):"unknown",
          fetchedAt:new Date().toISOString(),
          note:"Saved user/assistant text only. This is not an interactive mirror of a different Codex application.",
        });
      }
    }
    child.on("error",()=>finish(Error("CODEX_NOT_INSTALLED: The laptop could not start Codex. Check the CLI installation and login.")));
    child.on("exit",()=>{if(!done)finish(Error("CODEX_EXITED: Codex closed before returning this conversation. Verify the laptop CLI login."));});
    child.stdout.on("data",chunk=>{
      if(done)return;
      total+=chunk.length;
      if(total>MAX_OUTPUT)return finish(Error("CODEX_HISTORY_TOO_LARGE: This saved conversation is too large for a safe mobile preview."));
      buffer+=chunk.toString("utf8");
      let pos;
      while(!done && (pos=buffer.indexOf("\n"))>=0){
        const line=buffer.slice(0,pos).trim();
        buffer=buffer.slice(pos+1);
        if(!line)continue;
        if(line.length>MAX_OUTPUT)return finish(Error("CODEX_HISTORY_TOO_LARGE: The conversation response exceeds the limit."));
        try{handle(JSON.parse(line));}catch(e){
          if(e instanceof SyntaxError)continue;
          finish(Error("CODEX_HISTORY_INVALID: Unexpected Codex history response."));
        }
      }
    });
    child.stderr.on("data",()=>{}); // Never print stdout/CLI secrets.
    send({id:1,method:"initialize",params:{
      clientInfo:{name:"o_agent",title:"O-AGENT owner-approved saved conversation viewer",version:"0.6.2"},
    }});
  });
}
