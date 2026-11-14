import test from "node:test";
import assert from "node:assert/strict";
import {mkdtemp,writeFile,rm} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {randomUUID,createPublicKey,verify} from "node:crypto";
import {SignedCloudWorker,boundedProviderResult} from "../../saas-worker/src/worker.mjs";
import {enrollCloudWorker,readIdentity} from "../../saas-worker/src/enroll.mjs";
import {generateDeviceKeys,canonicalRequest} from "../src/device-crypto.mjs";

test("isolated cloud worker executes a single approved inventory with signed leases",
  {timeout:10000},async()=>{
  const directory=await mkdtemp(join(tmpdir(),"oagent-cloud-worker-"));
  try{
    await writeFile(join(directory,"README.md"),"testing only");
    const keys=generateDeviceKeys(),deviceId=randomUUID(),runId=randomUUID(),
      leaseToken=randomUUID();
    const observed=[];let claimed=false;
    const fakeFetch=async(url,opts)=>{
      const path=new URL(url).pathname,headers=opts.headers;
      const raw=opts.body||Buffer.alloc(0),timestamp=Number(headers["x-oagent-timestamp"]);
      const canonical=canonicalRequest({method:opts.method,path,
        timestamp,nonce:headers["x-oagent-nonce"],rawBody:raw});
      assert.equal(headers["x-oagent-device-id"],deviceId);
      assert.ok(verify(null,canonical,createPublicKey(keys.publicKeyPem),
        Buffer.from(headers["x-oagent-signature"],"base64url")));
      const data=opts.body?JSON.parse(raw.toString("utf8")):{};
      observed.push({path,data});
      if(path==="/v1/device/claim"){
        if(claimed)return Response.json({run:null});
        claimed=true;
        return Response.json({run:{id:runId,leaseToken,kind:"workspace_inventory",
          cwd:"",mode:"read_only",prompt:"",session_id:null}});
      }
      return Response.json(path.endsWith("/complete")?
        {status:"completed"}:{ok:true});
    };
    const worker=new SignedCloudWorker({
      origin:"https://agents.example",deviceId,privateKeyPem:keys.privateKeyPem,
      root:directory,fetchImpl:fakeFetch,env:{},wait:async()=>{},
    });
    await worker.initialize();
    const result=await worker.tick();
    assert.deepEqual(result,{claimed:true,completed:true});
    assert.ok(observed.some(x=>x.path==="/v1/device/capabilities" &&
      x.data.capabilities.includes("workspace_inventory")));
    assert.equal(observed.find(x=>x.path.endsWith("/complete")).data.result.entries[0].name,
      "README.md");
    assert.deepEqual(await worker.tick(),{claimed:false});
  }finally{await rm(directory,{recursive:true,force:true});}
});
test("cloud SDK worker transfers exact permissions and progress through signed API",
  {timeout:10000},async()=>{
  const folder=await mkdtemp(join(tmpdir(),"oagent-cloud-agent-"));
  try{
    const key=generateDeviceKeys(),id=randomUUID(),runId=randomUUID(),
      leaseToken=randomUUID(),approvalId=randomUUID();
    const paths=[];let permissionRequests=0;
    const worker=new SignedCloudWorker({
      origin:"https://agents.example",deviceId:id,
      privateKeyPem:key.privateKeyPem,root:folder,
      env:{OAGENT_ENABLE_CLAUDE_AGENT_SDK:"1"},
      fetchImpl:async(url,opts)=>{
        const path=new URL(url).pathname;
        paths.push(path);
        if(path.endsWith("/approvals")&&opts.method==="POST"){
          permissionRequests++;
          const body=JSON.parse(opts.body.toString());
          assert.equal(body.description,"Edit example.txt");
          return Response.json({approvalId,actionHash:"a".repeat(64)});
        }
        if(path==="/v1/device/approvals/"+approvalId)
          return Response.json({state:"approved"});
        return Response.json({status:"completed"});
      },
      providerRunner:async(task,callbacks)=>{
        assert.equal(task.parameters.cwd,folder);
        await callbacks.sendUpdate({type:"status",text:"started"});
        const approved=await callbacks.askPermission({
          id:"permission-123456",description:"Edit example.txt"});
        assert.equal(approved,true);
        return {providerStatus:"completed",sessionId:"native-session-12345",
          response:"finished"};
      },
      wait:async()=>{},
    });
    const result=await worker.execute({id:runId,leaseToken,
      kind:"claude_agent_turn",mode:"workspace_write",cwd:folder,
      prompt:"Edit a small test file",session_id:null});
    assert.equal(result.completed,true);
    assert.equal(permissionRequests,1);
    assert.ok(paths.includes("/v1/device/runs/"+runId+"/events"));
    assert.ok(paths.includes("/v1/device/runs/"+runId+"/complete"));
  }finally{await rm(folder,{recursive:true,force:true});}
});
test("a server-issued workspace outside the enrolled container is rejected",async()=>{
  const folder=await mkdtemp(join(tmpdir(),"oagent-root-"));
  const outside=await mkdtemp(join(tmpdir(),"oagent-outside-"));
  try{
    const key=generateDeviceKeys(),events=[];
    const worker=new SignedCloudWorker({
      origin:"https://agents.example",deviceId:randomUUID(),
      privateKeyPem:key.privateKeyPem,root:folder,
      env:{OAGENT_ENABLE_CLAUDE_AGENT_SDK:"1"},
      fetchImpl:async(url,opts)=>{
        events.push({path:new URL(url).pathname,body:JSON.parse(opts.body.toString())});
        return Response.json({status:"failed"});
      },
      providerRunner:async()=>{throw Error("Provider must not execute");},
    });
    const result=await worker.execute({
      id:randomUUID(),leaseToken:randomUUID(),kind:"claude_agent_turn",
      mode:"read_only",cwd:outside,prompt:"Read",session_id:null,
    });
    assert.equal(result.completed,false);
    assert.match(result.error,/outside enrolled/);
    assert.equal(events.length,1);
    assert.equal(events[0].body.ok,false);
  }finally{
    await rm(folder,{recursive:true,force:true});
    await rm(outside,{recursive:true,force:true});
  }
});

test("owner-approved free worker enrolls automatically and securely reuses its local key",async()=>{
  const folder=await mkdtemp(join(tmpdir(),"oagent-free-enroll-"));
  try{
    const path=join(folder,"identity.json");
    const assigned=randomUUID();
    const requests=[];
    const fetchImpl=async(url,opts)=>{
      requests.push(new URL(url).pathname);
      if(url.endsWith("/enrollments"))
        return Response.json({pairingToken:"oen_"+"A".repeat(43),expiresInSeconds:600});
      if(url.endsWith("/status"))
        return Response.json({approved:true,deviceId:assigned});
      throw Error("Unexpected enrollment API");
    };
    const messages=[];
    const result=await enrollCloudWorker({
      origin:"https://laptop.example.ts.net",name:"Private laptop",
      path,now:()=>1700000000000,wait:async()=>{},fetchImpl,
      notify:value=>messages.push(String(value)),
    });
    assert.equal(result.deviceId,assigned);
    assert.equal((await readIdentity(path)).deviceId,assigned);
    assert.ok((await readIdentity(path)).privateKeyPem.includes("PRIVATE KEY"));
    assert.ok(messages.some(x=>x.includes("#pair=oen_")));
    const repeated=await enrollCloudWorker({
      origin:"https://laptop.example.ts.net",path,fetchImpl,
    });
    assert.equal(repeated.alreadyEnrolled,true);
    assert.equal(requests.length,2);
  }finally{await rm(folder,{recursive:true,force:true});}
});

test("oversized real provider output is preview-limited, not misreported as failed",()=>{
  const result={providerStatus:"completed",sessionId:"resume-abcdefgh",
    response:"Very long provider response. ".repeat(10000)};
  const limited=boundedProviderResult(result);
  assert.equal(limited.providerStatus,"completed");
  assert.equal(limited.sessionId,"resume-abcdefgh");
  assert.equal(limited.truncated,true);
  assert.ok(Buffer.byteLength(JSON.stringify(limited))<10000);
  assert.equal(boundedProviderResult({providerStatus:"completed",response:"ok"}).response,"ok");
});
test("forbidden operation does not falsely revoke a valid signed device",async()=>{
  const folder=await mkdtemp(join(tmpdir(),"oagent-forbidden-"));
  try{
    const keys=generateDeviceKeys();
    const worker=new SignedCloudWorker({
      origin:"https://laptop.example.ts.net",deviceId:randomUUID(),
      privateKeyPem:keys.privateKeyPem,root:folder,
      fetchImpl:async()=>Response.json({error:"Scope denied"},{status:403}),
    });
    await assert.rejects(()=>worker.api("/v1/device/heartbeat"),
      /forbidden/);
    assert.equal(worker.revoked,false);
  }finally{await rm(folder,{recursive:true,force:true});}
});
test("worker rate-limits very long native progress without inventing completion",async()=>{
  const folder=await mkdtemp(join(tmpdir(),"oagent-progress-"));
  try{
    const events=[];
    const worker=new SignedCloudWorker({
      origin:"https://laptop.example.ts.net",deviceId:randomUUID(),
      privateKeyPem:generateDeviceKeys().privateKeyPem,root:folder,
      env:{OAGENT_ENABLE_CLAUDE_AGENT_SDK:"1"},
      fetchImpl:async(url,opts)=>{
        const pathname=new URL(url).pathname;
        if(pathname.endsWith("/events"))
          events.push(JSON.parse(opts.body.toString("utf8")));
        return Response.json({status:"completed"});
      },
      providerRunner:async(_task,cb)=>{
        await cb.sendUpdate({type:"agent_delta",text:"delta".repeat(2400)});
        await cb.sendUpdate({type:"invalid_event",text:"details"});
        return {providerStatus:"completed",response:"Finished"};
      },
    });
    const result=await worker.execute({id:randomUUID(),
      leaseToken:randomUUID(),kind:"claude_agent_turn",
      cwd:folder,mode:"read_only",prompt:"Read",session_id:null});
    assert.equal(result.completed,true);
    assert.ok(events.length>=2);
    assert.ok(events.every(e=>e.text.length<=1800));
    assert.equal(events.at(-1).kind,"status");
  }finally{await rm(folder,{recursive:true,force:true});}
});
