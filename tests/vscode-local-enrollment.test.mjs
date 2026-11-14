import test from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";
const require=createRequire(import.meta.url);
const {readLocalEnrollment,verifyLocalBackend}=require("../apps/vscode/src/local-enrollment.cjs");

test("local enrollment only works on the local Windows extension host",async()=>{
  let called=0;
  const runner=async()=>{called++;return{stdout:"{}"};};
  await assert.rejects(()=>readLocalEnrollment({platform:"linux",runner}),/local VS Code/);
  await assert.rejects(()=>readLocalEnrollment({platform:"win32",remoteName:"ssh-remote",runner}),/local VS Code/);
  assert.equal(called,0);
});
test("local enrollment invokes only the packaged helper with no user-supplied arguments",async()=>{
  const secret="a".repeat(64);
  let args;
  const result=await readLocalEnrollment({
    platform:"win32",
    runner:async(file,argumentsList,options)=>{
      args={file,argumentsList,options};
      return {stdout:JSON.stringify({origin:"http://127.0.0.1:8787",workerToken:secret})};
    },
  });
  assert.deepEqual(result,{url:"http://127.0.0.1:8787",token:secret});
  assert.equal(args.file,"powershell.exe");
  assert.ok(args.argumentsList.includes("-NonInteractive"));
  assert.ok(args.argumentsList.includes("-File"));
  assert.match(args.argumentsList.at(-1),/read-local-worker\.ps1$/);
  assert.equal(args.options.windowsHide,true);
  assert.equal(args.argumentsList.some(x=>x.includes(secret)),false);
});
test("local enrollment never accepts a remote origin, malformed credentials or error leakage",async()=>{
  for(const value of [
    {origin:"https://example.com",workerToken:"x".repeat(64)},
    {origin:"http://localhost:8787",workerToken:"x".repeat(64)},
    {origin:"http://127.0.0.1:8787",workerToken:"bad"},
    {origin:"http://127.0.0.1:8787",workerToken:"x".repeat(25)+"\n"},
  ]){
    await assert.rejects(()=>readLocalEnrollment({
      platform:"win32",runner:async()=>({stdout:JSON.stringify(value)}),
    }),/local|credential/i);
  }
  await assert.rejects(()=>readLocalEnrollment({
    platform:"win32",runner:async()=>{throw Error("SECRET-DO-NOT-LOG")},
  }),error=>{
    assert.doesNotMatch(error.message,/SECRET-DO-NOT-LOG/);
    return true;
  });
});
test("auto-connect checks the actual local O-AGENT service before importing secrets",async()=>{
  assert.equal(await verifyLocalBackend("http://127.0.0.1:8787",{
    fetchImpl:async(url,opts)=>{
      assert.equal(url.origin,"http://127.0.0.1:8787");
      assert.equal(opts.redirect,"error");
      assert.equal(opts.method,"GET");
      return {ok:true,json:async()=>({service:"oagent-control-plane",status:"ok"})};
    },
  }),true);
  await assert.rejects(()=>verifyLocalBackend("http://127.0.0.1:8787",{
    fetchImpl:async()=>({ok:true,json:async()=>({service:"untrusted"})}),
  }),/not serving/);
  await assert.rejects(()=>verifyLocalBackend("https://example.com"),/loopback/);
  await assert.rejects(()=>verifyLocalBackend("http://127.0.0.1:8787",{
    fetchImpl:async()=>{throw Error("socket failed");},
  }),/Start O-AGENT.cmd/);
});
