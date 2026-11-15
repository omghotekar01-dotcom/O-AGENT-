import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {launchOneClick,prepareDocker,startExistingRemoteGateway} from "../scripts/one-click-pilot.mjs";

const file=path=>readFileSync(new URL("../"+path,import.meta.url),"utf8");

test("one double-click starts Docker, private server, native login, phone instructions, then worker",async()=>{
  const steps=[],messages=[];
  await launchOneClick({
    prepare:async()=>steps.push("docker"),
    start:async()=>{steps.push("server");return {ready:true}},
    register:async()=>{steps.push("oauth");return {created:true}},
    previousGateway:async()=>steps.push("previous-gateway"),
    mobile:async()=>steps.push("phone"),
    worker:async()=>steps.push("worker"),
    print:msg=>messages.push(msg),
  });
  assert.deepEqual(steps,["docker","server","oauth","previous-gateway","phone","worker"]);
  assert.ok(messages.some(s=>s.includes("Native phone login registered")));
  assert.ok(messages.some(s=>s.includes("fingerprint")));
});

test("a failing prerequisite never runs the server or trusted worker",async()=>{
  const steps=[];
  await assert.rejects(launchOneClick({
    prepare:async()=>{steps.push("docker");throw Error("Missing Docker");},
    start:async()=>{steps.push("server");return {ready:true}},
    worker:async()=>steps.push("worker"),
    print:()=>{},
  }),/Missing Docker/);
  assert.deepEqual(steps,["docker"]);
});

test("server failing readiness prevents native login and worker enrollment",async()=>{
  const steps=[];
  await assert.rejects(launchOneClick({
    prepare:async()=>{},
    start:async()=>({ready:false,checks:[]}),
    register:async()=>steps.push("oauth"),
    worker:async()=>steps.push("worker"),
    print:()=>{},
  }),/not ready/);
  assert.deepEqual(steps,[]);
});

test("OAuth registration error never starts a worker",async()=>{
  let worker=false;
  await assert.rejects(launchOneClick({
    prepare:async()=>{},
    start:async()=>({ready:true}),
    register:async()=>{throw Error("Native OAuth client unavailable");},
    worker:async()=>{worker=true;},
    print:()=>{},
  }),/OAuth client unavailable/);
  assert.equal(worker,false);
});

test("existing Docker engine is reused without launching the Desktop UI",async()=>{
  let opened=false;
  await prepareDocker({ready:()=>true,start:()=>{opened=true;}});
  assert.equal(opened,false);
});

test("installed Docker Desktop is started only if the engine is offline",async()=>{
  let count=0,started=0,waited=0;
  await prepareDocker({
    ready:()=>++count>=4,platform:"win32",exists:()=>true,
    env:{ProgramFiles:"C:\\Program Files"},
    start:()=>{started++;return {unref(){}};},
    wait:async()=>{waited++;},print:()=>{},
  });
  assert.equal(started,1);
  assert.equal(waited,2);
});

test("missing Docker on Windows gives remedy without installing anything",async()=>{
  await assert.rejects(prepareDocker({
    ready:()=>false,platform:"win32",exists:()=>false,
    print:()=>{},
  }),/Install Docker Desktop/);
});

test("Windows entry point never deletes Docker data, resets Tailscale or calls multiple CMDs",()=>{
  const startup=file("START-O-AGENT.cmd");
  const worker=file("scripts/select-oagent-workspace.ps1");
  const helper=file("scripts/one-click-pilot.mjs");
  assert.match(startup,/scripts\\one-click-pilot\.mjs/);
  assert.doesNotMatch(startup,/call .*\.cmd|docker compose down|docker system prune/i);
  assert.match(worker,/trusted-workspace\.txt/);
  assert.match(worker,/Local\\OAgentPrivatePilotWorker/);
  assert.match(worker,/WaitOne\(0\)/);
  assert.match(worker,/OAGENT_CHANGE_WORKSPACE/);
  assert.match(helper,/ensureNativeClient/);
  assert.match(helper,/startWindowsWorker/);
  for(const script of [startup,worker,helper])
    assert.doesNotMatch(script,/docker compose down -v|tailscale (?:serve )?reset|tailscale funnel/i);
});

test("one-click starts the consented older gateway only when local configuration exists",async()=>{
  const events=[];
  const success=await startExistingRemoteGateway({
    platform:"win32",env:{LOCALAPPDATA:"C:\\\\Users\\\\test\\\\AppData\\\\Local"},
    exists:()=>true,
    command:(_program,args)=>{events.push(args);const handlers={};
      queueMicrotask(()=>handlers.exit?.(0,null));
      return {once:(name,cb)=>{handlers[name]=cb;}};
    },
    print:()=>{},
  });
  assert.equal(success,true);
  assert.equal(events.length,1);
  assert.ok(events[0].includes("-File"));
  let called=false;
  const disabled=await startExistingRemoteGateway({
    platform:"win32",env:{LOCALAPPDATA:"x",OAGENT_START_PREVIOUS_WORKSPACE:"0"},
    exists:()=>true,command:()=>{called=true;},
  });
  assert.equal(disabled,false);
  assert.equal(called,false);
  const missing=await startExistingRemoteGateway({
    platform:"win32",env:{LOCALAPPDATA:"x"},
    exists:()=>false,command:()=>{called=true;},print:()=>{},
  });
  assert.equal(missing,false);
  assert.equal(called,false);
});
