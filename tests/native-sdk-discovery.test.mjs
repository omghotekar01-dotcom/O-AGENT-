import test from "node:test";
import assert from "node:assert/strict";
import {discoverNativeSessions} from "../apps/gateway/src/native-session-discovery.mjs";
import {ControlPlane} from "../apps/control-plane/src/core.mjs";
import {ProjectHub} from "../apps/control-plane/src/project-hub.mjs";

test("official SDK listing is scoped to enrolled root and omits secrets", async () => {
  let stopCount=0, clientOptions;
  const data=await discoverNativeSessions({
    root:"/work", realpathImpl:async path=>path,
    env:{OAGENT_ENABLE_CLAUDE_AGENT_SDK:"1",
      OAGENT_ENABLE_COPILOT_SDK:"1",
      OAGENT_WORKER_TOKEN:"private-worker-secret",PATH:"/usr/bin"},
    importSdk:async name=>name.includes("anthropic")?{
      listSessions:async opts=>{
        assert.equal(opts.limit,120);
        return [
          {sessionId:"claude-session-1234",cwd:"/work/app",summary:"Build page",
            lastModified:1730000000000},
          {sessionId:"claude-outside-1234",cwd:"/secret",summary:"PRIVATE"},
          {sessionId:"bad",cwd:"/work/app"},
        ];
      },
    }:{CopilotClient:class {
      constructor(options){clientOptions=options;}
      async start(){}
      async listSessions(){return [
        {sessionId:"copilot-session-1234",context:{cwd:"/work/app"},
          summary:"Repair",modifiedTime:new Date("2026-11-14T02:00:00Z")},
      ];}
      async stop(){stopCount++;}
    }},
  });
  assert.equal(data.sessions.length,2);
  assert.equal(data.sessions[0].kind,"claude_agent_turn");
  assert.equal(data.sessions[1].kind,"copilot_sdk_turn");
  assert.equal(data.sessions[1].modifiedAt,"2026-11-14T02:00:00.000Z");
  assert.equal(stopCount,1);
  assert.equal(clientOptions.env.OAGENT_WORKER_TOKEN,undefined);
  assert.doesNotMatch(JSON.stringify(data),/PRIVATE|private-worker-secret/);
  assert.equal(data.states.claude_agent_turn,"metadata_available");
  assert.equal(data.states.copilot_sdk_turn,"metadata_available");
});

test("SDK errors do not leak provider credentials",async()=>{
  const data=await discoverNativeSessions({
    root:"/work",realpathImpl:async x=>x,
    env:{OAGENT_ENABLE_CLAUDE_AGENT_SDK:"1"},
    importSdk:async()=>{throw Error("SECRET-account-credential");},
  });
  assert.deepEqual(data.sessions,[]);
  assert.equal(data.states.claude_agent_turn,"sdk_unavailable");
  assert.doesNotMatch(JSON.stringify(data),/SECRET/);
});

test("authenticated SDK session metadata is bounded, ephemeral, and only fresh when online",()=>{
  let now=1000000;
  const core=new ControlPlane({},()=>{},()=>now);
  core.registerWorker({id:"laptop-1",name:"Laptop",capabilities:["claude_agent_turn"]});
  const hub=new ProjectHub(core,{status:()=>({configured:false})},
    {env:{},now:()=>now});
  const payload={sessions:[{kind:"claude_agent_turn",
    sessionId:"claude-session-1234",cwd:"/work/app",
    title:"Existing saved session",
    modifiedAt:"2026-11-14T02:00:00.000Z"}],
    states:{claude_agent_turn:"metadata_available"}};
  assert.deepEqual(hub.publishNativeSessions("laptop-1",payload),
    {accepted:1,ephemeral:true});
  const overview=hub.remoteOverview();
  assert.equal(overview.nativeSessions.length,1);
  assert.equal(overview.nativeSessions[0].provenance,"sdk_saved_session");
  assert.equal(overview.nativeSessions[0].resumeEligible,true);
  assert.equal(overview.sdkDiscovery[0].states.claude_agent_turn,
    "metadata_available");
  assert.equal(core.data.nativeSdkSnapshots,undefined);
  now+=301000;
  assert.equal(hub.remoteOverview().nativeSessions.length,0);
  assert.throws(()=>hub.publishNativeSessions("unknown",payload),/online/);
  assert.throws(()=>hub.publishNativeSessions("laptop-1",payload),/online/);
});

test("untrusted SDK session claims and large payloads fail closed",()=>{
  const core=new ControlPlane();
  core.registerWorker({id:"laptop-1",name:"Laptop",capabilities:["claude_agent_turn"]});
  const hub=new ProjectHub(core,{status:()=>({configured:false})});
  const row={kind:"copilot_sdk_turn",sessionId:"copilot-123456",
    cwd:"/work/app",title:"Saved"};
  assert.throws(()=>hub.publishNativeSessions("laptop-1",
    {sessions:[row],states:{}}),/Invalid/);
  assert.throws(()=>hub.publishNativeSessions("laptop-1",
    {sessions:[{...row,kind:"claude_agent_turn",title:"x".repeat(300)}],
      states:{}}),/Invalid/);
  assert.throws(()=>hub.publishNativeSessions("laptop-1",
    {sessions:Array(41).fill({...row,kind:"claude_agent_turn"}),states:{}}),
    /Invalid/);
});
