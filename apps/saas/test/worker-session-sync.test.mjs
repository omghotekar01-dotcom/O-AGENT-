import test from "node:test";
import assert from "node:assert/strict";
import {mkdtemp,rm} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {randomUUID} from "node:crypto";
import {generateDeviceKeys} from "../src/device-crypto.mjs";
import {SignedCloudWorker} from "../../saas-worker/src/worker.mjs";

test("idle signed worker syncs real saved sessions and enables only verified Codex continuation",async()=>{
  const root=await mkdtemp(join(tmpdir(),"oagent-sync-"));
  try{
    const keys=generateDeviceKeys(),id=randomUUID(),posted=[];
    let scans=0;
    const worker=new SignedCloudWorker({
      origin:"https://worker.example.ts.net",root,
      deviceId:id,privateKeyPem:keys.privateKeyPem,
      env:{OAGENT_ENABLE_CODEX_DISCOVERY:"1"},
      now:()=>100000,
      sessionReader:async({root:requested})=>{
        assert.equal(requested,root);
        scans++;
        return [{sessionId:"saved-thread-12345",cwd:root,
          title:"Real Codex task",preview:"Implement native controls",
          sourceKind:"vscode",updatedAt:"2026-11-15T04:00:00Z",
          messages:[{role:"user",text:"Continue the task"}]}];
      },
      fetchImpl:async(url,options)=>{
        const path=new URL(url).pathname;
        assert.equal(options.headers["x-oagent-device-id"],id);
        if(options.body)posted.push({path,body:JSON.parse(options.body.toString())});
        if(path==="/v1/device/claim")return Response.json({run:null});
        return Response.json({ok:true});
      },
    });
    assert.deepEqual(await worker.tick(),{claimed:false});
    assert.equal(scans,1);
    assert.equal(posted.filter(x=>x.path==="/v1/device/sessions").length,1);
    assert.equal(posted.filter(x=>x.path==="/v1/device/capabilities").length,1);
    assert.ok(posted.find(x=>x.path==="/v1/device/capabilities")
      .body.capabilities.includes("codex_cli_turn"));
    assert.equal(worker.env.OAGENT_ENABLE_CODEX_LOCAL_SYNC,"1");
    assert.deepEqual(await worker.tick(),{claimed:false});
    assert.equal(scans,1,"throttled discovery must not repeatedly spawn Codex");
    assert.equal(posted.filter(x=>x.path==="/v1/device/sessions").length,1);
  }finally{await rm(root,{recursive:true,force:true});}
});
test("explicit disabled Codex execution remains off even when saved history can be read",async()=>{
  const root=await mkdtemp(join(tmpdir(),"oagent-no-exec-"));
  try{
    const keys=generateDeviceKeys(),posted=[];
    const worker=new SignedCloudWorker({
      origin:"https://worker.example.ts.net",root,
      deviceId:randomUUID(),privateKeyPem:keys.privateKeyPem,
      env:{OAGENT_ENABLE_CODEX_DISCOVERY:"1",
        OAGENT_ENABLE_CODEX_LOCAL_SYNC:"0"},
      now:()=>200000,
      sessionReader:async()=>[{
        sessionId:"saved-thread-98765",cwd:root,
        title:"Saved thread",preview:"",sourceKind:"cli",
        updatedAt:"2026-11-15T04:00:00Z",messages:[],
      }],
      fetchImpl:async(url,options)=>{
        const path=new URL(url).pathname;
        if(options.body)posted.push(path);
        if(path==="/v1/device/claim")return Response.json({run:null});
        return Response.json({ok:true});
      },
    });
    await worker.tick();
    assert.ok(posted.includes("/v1/device/sessions"));
    assert.equal(posted.includes("/v1/device/capabilities"),false);
    assert.equal(worker.env.OAGENT_ENABLE_CODEX_LOCAL_SYNC,"0");
  }finally{await rm(root,{recursive:true,force:true});}
});
