import test from "node:test";
import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { conversationMessages, readCodexHistory } from "../apps/gateway/src/codex-history.mjs";
import { explainCodexError } from "../apps/gateway/src/codex-errors.mjs";
import { ControlPlane } from "../apps/control-plane/src/core.mjs";
import { ProjectHub } from "../apps/control-plane/src/project-hub.mjs";

const sessionId = "11111111-2222-4333-8444-555555555555";
const cwd = "C:\\Users\\ASUS\\Projects\\O-AGENT";
const history = {
  id: sessionId,
  status: { type: "notLoaded" },
  turns: [
    { id:"turn-1",items: [
      {type:"userMessage",content:[{type:"text",text:"Please check the app"}]},
      {type:"reasoning",content:["SECRET REASONING"],summary:["PRIVATE"]},
      {type:"commandExecution",command:"cat /secrets.txt",aggregatedOutput:"SECRET_TOOL_OUTPUT"},
      {type:"agentMessage",phase:"final_answer",text:"I checked the project."},
    ]},
    {id:"turn-2",items:[
      {type:"userMessage",content:[{type:"text",text:"What comes next?"}]},
      {type:"mcpToolCall",arguments:{secret:"DO NOT RETURN"}},
      {type:"agentMessage",text:"Run Flutter tests and review."},
    ]},
  ],
};
const task = {kind:"codex_cli_history",parameters:{sessionId}};
function fakeServer(resultOrError, pageOverride = null) {
  const child = new EventEmitter();
  const requests = [];
  child.stdin = {write(text) {
    const m=JSON.parse(text);requests.push(m);
    if(m.id===1)queueMicrotask(()=>child.stdout.emit("data",
      Buffer.from(JSON.stringify({id:1,result:{}})+"\n")));
    if(m.id===2)queueMicrotask(()=>child.stdout.emit("data",
      Buffer.from(JSON.stringify(resultOrError)+"\n")));
    if(m.id===3)queueMicrotask(()=>child.stdout.emit("data",
      Buffer.from(JSON.stringify(pageOverride ?? {id:3,result:{
        data:history.turns.slice().reverse(),nextCursor:null
      }})+"\n")));
  },end(){}};
  child.stdout=new EventEmitter();
  child.stderr=new EventEmitter();
  child.kill=()=>true;
  return {child,requests};
}
test("Codex history reads persisted real user/assistant messages without resuming or starting work",async()=>{
  const f=fakeServer({id:2,result:{thread:history}});
  const result=await readCodexHistory(task,{
    spawnImpl:(_,__,opt)=>{
      assert.equal(opt.env.OAGENT_WORKER_TOKEN,undefined);
      assert.equal(opt.env.OPENAI_API_KEY,undefined);
      assert.equal(opt.env.OAGENT_VAULT_KEY_BASE64,undefined);
      return f.child;
    },isWindows:true,timeoutMs:2000,
    env:{OAGENT_WORKER_TOKEN:"private",OPENAI_API_KEY:"private",
      OAGENT_VAULT_KEY_BASE64:"private",PATH:"demo"},
  });
  assert.deepEqual(f.requests.map(x=>x.method),
    ["initialize","initialized","thread/read","thread/turns/list"]);
  assert.equal(f.requests[2].params.threadId,sessionId);
  assert.equal(f.requests[2].params.includeTurns,false);
  assert.equal(f.requests[3].params.itemsView,"summary");
  assert.equal(f.requests[3].params.sortDirection,"desc");
  assert.equal(f.requests[0].params.capabilities.experimentalApi,true);
  assert.deepEqual(result.messages.map(x=>x.role),
    ["user","assistant","user","assistant"]);
  assert.equal(result.messages[0].text,"Please check the app");
  assert.equal(result.messages[3].text,"Run Flutter tests and review.");
  assert.doesNotMatch(JSON.stringify(result),/SECRET|DO NOT RETURN|secrets.txt/);
  assert.equal(result.observedStatus,"notLoaded");
});
test("Codex read-only history can be viewed even when writing lock blocks turn resume",async()=>{
  const f=fakeServer({id:2,result:{thread:history}});
  const result=await readCodexHistory(task,{
    spawnImpl:()=>f.child,isWindows:false,timeoutMs:2000,
  });
  assert.equal(result.messages.length,4);
  assert.equal(f.requests.find(x=>x.method==="thread/resume"),undefined);
  assert.equal(f.requests.find(x=>x.method==="turn/start"),undefined);
});
test("Codex history refuses mismatched session and does not mix user chat data",async()=>{
  const f=fakeServer({id:2,result:{thread:{...history,id:"another-owner-thread"}}});
  await assert.rejects(readCodexHistory(task,{
    spawnImpl:()=>f.child,isWindows:false,timeoutMs:2000,
  }),/different conversation/);
});
test("large Codex histories show a bounded recent page without loading all turns",async()=>{
  const recent={...history, turns:[history.turns.at(-1)]};
  const f=fakeServer({id:2,result:{thread:{id:sessionId,status:{type:"notLoaded"},turns:[]}}},
    {id:3,result:{data:recent.turns,nextCursor:"older-page-cursor"}});
  const result=await readCodexHistory(task,{spawnImpl:()=>f.child,isWindows:false,timeoutMs:2000});
  assert.equal(result.truncated,true);
  assert.equal(result.messages.length,2);
  assert.equal(result.messages[0].text,"What comes next?");
  assert.equal(f.requests.some(x=>x.method==="thread/resume"),false);
});

test("legacy Codex history falls back after unsupported pagination",async()=>{
  const f=fakeServer({id:2,result:{thread:{id:sessionId,status:{type:"notLoaded"}}}},
    {id:3,error:{code:-32601,message:"Method not found"}});
  const originalWrite=f.child.stdin.write;
  f.child.stdin.write=(line)=>{
    const m=JSON.parse(line);
    if(m.id===4){
      f.requests.push(m);
      queueMicrotask(()=>f.child.stdout.emit("data",
        Buffer.from(JSON.stringify({id:4,result:{thread:history}})+"\\n".replace("\\\\n","\\n"))));
    } else originalWrite(line);
  };
  const result=await readCodexHistory(task,{spawnImpl:()=>f.child,isWindows:false,timeoutMs:2000});
  assert.equal(result.messages.length,4);
  assert.equal(f.requests.at(-1).params.includeTurns,true);
});

test("provider errors explain real conditions without echoing raw secrets",async()=>{
  const cases=[
    [{code:-32600,message:"thread already in use: SECRET_PATH"},
      /CODEX_SESSION_BUSY.*owned by another Codex process/],
    [{code:-32601,message:"Method not found: PRIVATE"},
      /CODEX_UPDATE_REQUIRED/],
    [{code:-32602,message:"invalid params PRIVATE"},
      /CODEX_PROTOCOL_ERROR/],
    [{code:-32000,message:"model provider mismatch for SECRET_ACCOUNT"},
      /CODEX_MODEL_MISMATCH/],
    [{code:500,message:"UNCLASSIFIED_SECRET_TOKEN=123456"},
      /CODEX_PROVIDER_ERROR/],
  ];
  for(const [input,expected] of cases){
    const result=explainCodexError(input);
    assert.match(result,expected);
    assert.doesNotMatch(result,/SECRET_PATH|PRIVATE|SECRET_ACCOUNT|SECRET_TOKEN/);
  }
});
test("one-tap phone history is owner scoped and read-only, with no extra approval or billing",()=>{
  let now=1800000000000;
  const core=new ControlPlane({},()=>{},()=>now);
  core.registerWorker({id:"my-laptop",name:"Authorized laptop",
    capabilities:["system_info","codex_cli_turn","codex_cli_history"]});
  const hub=new ProjectHub(core,{},{
    env:{OAGENT_ENABLE_CODEX_LOCAL_SYNC:"1"},now:()=>now,
  });
  hub.publishCodexLocal("my-laptop",{sessions:[{
    id:sessionId,cwd,title:"Actual O-AGENT work",state:"notLoaded",
  }]});
  const project=Object.values(core.data.codexLocalProjects)[0];
  const first=hub.requestLocalCodexHistory({projectId:project.id,sessionId},
    "history-request-0123456789");
  assert.equal(first.status,"queued");
  const duplicate=hub.requestLocalCodexHistory({projectId:project.id,sessionId},
    "different-idempotency-key-98765");
  assert.equal(duplicate.id,first.id);
  const claimed=core.claim("my-laptop");assert.equal(claimed.id,first.id);
  assert.equal(claimed.parameters.prompt,undefined);
  core.finish("my-laptop",claimed.id,{ok:true,result:{
    provider:"codex_cli",sessionId,messages:[{role:"user",text:"Real text"}],
  }});
  assert.equal(core.getTask(claimed.id).result.messages[0].text,"Real text");
  assert.doesNotMatch(JSON.stringify(core.data), /Real text/,
    "Saved conversation text must never enter durable backend tasks");
  now += 30 * 60 * 1000 + 1;
  assert.equal(core.getTask(claimed.id).result, null);
  assert.equal(core.getTask(claimed.id).historyExpired, true);
  now -= 30 * 60 * 1000 + 1;
  assert.throws(()=>hub.requestLocalCodexHistory({
    projectId:project.id,sessionId:"another-session-123456"},
    "invalid-history-key-1234"),/not among/);
  now+=125000;
  assert.throws(()=>hub.requestLocalCodexHistory({
    projectId:project.id,sessionId},"stale-key-12345678901234"),/stale/);
});
test("one explicit prompt confirmation queues exact Codex task and retains tool approval gate",()=>{
  const core=new ControlPlane();
  core.registerWorker({id:"my-laptop",name:"Authorized laptop",
    capabilities:["codex_cli_turn","codex_cli_history"]});
  const hub=new ProjectHub(core,{},{
    env:{OAGENT_ENABLE_CODEX_LOCAL_SYNC:"1"},
  });
  hub.publishCodexLocal("my-laptop",{sessions:[{
    id:sessionId,cwd,title:"Actual session",state:"notLoaded",
  }]});
  const project=Object.values(core.data.codexLocalProjects)[0];
  const body={
    projectId:project.id,sessionId,
    prompt:"Summarize the project and do not edit files",mode:"read_only",
  };
  assert.throws(()=>hub.confirmLocalCodexTurn(body,
    "explicit-consent-missing-12345"),/explicitly confirm/);
  const input={...body,consent:"authorize-exact-prompt"};
  const submitted=hub.confirmLocalCodexTurn(input,"explicit-approved-123456");
  assert.equal(submitted.status,"queued");
  assert.equal(submitted.parameters.prompt,body.prompt);
  assert.equal(hub.confirmLocalCodexTurn(input,"explicit-approved-123456").id,
    submitted.id);
  assert.equal(core.claim("my-laptop").status,"running");
  assert.throws(()=>core.requestCodexApproval("my-laptop",submitted.id,{
    id:"write-request-12345678",kind:"file_change",description:"Write a file",
  }),/Read-only/);
});
test("history message preview excludes tool/reasoning and is bounded",()=>{
  const turns=Array.from({length:80},(_,i)=>({items:[
    {type:"userMessage",content:[{type:"text",text:"user "+i+" x".repeat(7000)}]},
    {type:"agentMessage",text:"reply "+i+" y".repeat(9000)},
  ]}));
  const result=conversationMessages({turns});
  assert.equal(result.truncated,true);
  assert.ok(JSON.stringify(result).length<18000);
  assert.ok(result.messages.length<=32);
  assert.equal(result.messages.at(-1).role,"assistant");
});
