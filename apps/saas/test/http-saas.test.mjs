import test from "node:test";
import assert from "node:assert/strict";
import {randomUUID} from "node:crypto";
import {Pool} from "pg";
import {migrate} from "../src/store.mjs";
import {makeSaasServer} from "../src/server.mjs";
import {generateDeviceKeys,deviceHeaders} from "../src/device-crypto.mjs";

test("real HTTP + PostgreSQL: OIDC owner, exact fingerprint pairing, signed worker and native approvals",
  {timeout:45000,skip:!process.env.OAGENT_TEST_DATABASE_URL},async()=>{
  const admin=new Pool({connectionString:process.env.OAGENT_TEST_DATABASE_URL});
  let pool,app;
  try {
    await migrate(admin);
    await admin.query("DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='oagent_http_test') THEN CREATE ROLE oagent_http_test LOGIN PASSWORD 'only-ci-not-for-public' NOSUPERUSER NOBYPASSRLS; END IF; END $$");
    await admin.query("GRANT USAGE ON SCHEMA public TO oagent_http_test");
    await admin.query("GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA public TO oagent_http_test");
    await admin.query("GRANT USAGE,SELECT ON ALL SEQUENCES IN SCHEMA public TO oagent_http_test");
    const db=new URL(process.env.OAGENT_TEST_DATABASE_URL);
    db.username="oagent_http_test";db.password="only-ci-not-for-public";
    pool=new Pool({connectionString:db.href});
    const ownerId="owner-"+randomUUID(),otherId="another-"+randomUUID();
    const config={
      publicOrigin:"http://127.0.0.1",issuer:"https://auth.test/",jwksUrl:"https://auth.test/jwks",
      audience:"oagent-api",clientIds:["client-test"],webAuth:null,
    };
    const authenticate=async(header,scope)=>{
      const subject=header==="Bearer owner-user"?ownerId:
        header==="Bearer other-user"?otherId:null;
      if(!subject)throw Object.assign(Error("Not authenticated"),{status:401});
      return {issuer:config.issuer,subject,
        clientId:"client-test",scopes:new Set(["oagent:read","oagent:operate"]),
        expiresAt:Date.now()+60000};
    };
    app=makeSaasServer({config,pool,authenticate});
    await new Promise(resolve=>app.server.listen(0,"127.0.0.1",resolve));
    config.publicOrigin="http://127.0.0.1:"+app.server.address().port;
    const url=config.publicOrigin,keys=generateDeviceKeys();
    async function request(path,{method="GET",token,body,headers={}}={}){
      const r=await fetch(url+path,{
        method,headers:{
          ...(token?{authorization:"Bearer "+token}:{}),
          ...(body!==undefined?{"content-type":"application/json"}:{}),...headers,
        },...(body!==undefined?{body:JSON.stringify(body)}:{}),
      });
      return {status:r.status,data:await r.json()};
    }
    const health=await request("/health/ready");
    assert.equal(health.status,200);
    const missing=await request("/v1/devices");
    assert.equal(missing.status,401);
    const metadata=await request("/.well-known/oauth-protected-resource");
    assert.equal(metadata.status,200);
    assert.equal(metadata.data.resource,url+"/mcp");
    const started=await request("/v1/devices/enrollments",{
      method:"POST",body:{name:"Isolated test worker",publicKeyPem:keys.publicKeyPem},
    });
    assert.equal(started.status,201,JSON.stringify(started.data));
    const pairingToken=started.data.pairingToken;
    const ownerView=await request("/v1/devices/enrollments/inspect",{
      method:"POST",token:"owner-user",body:{pairingToken},
    });
    assert.equal(ownerView.status,200);
    const fingerprint=ownerView.data.fingerprint;
    assert.match(fingerprint,/^[a-f0-9]{24}$/);
    const wrong=await request("/v1/devices/enrollments/approve",{
      method:"POST",token:"owner-user",
      body:{pairingToken,expectedFingerprint:"000000000000000000000000"},
    });
    assert.equal(wrong.status,409);
    const approved=await request("/v1/devices/enrollments/approve",{
      method:"POST",token:"owner-user",
      body:{pairingToken,expectedFingerprint:fingerprint},
    });
    assert.equal(approved.status,201);
    const deviceId=approved.data.deviceId;
    const idResult=await request("/v1/devices/enrollments/status",{
      method:"POST",body:{pairingToken},
    });
    assert.equal(idResult.data.deviceId,deviceId);
    const reused=await request("/v1/devices/enrollments/approve",{
      method:"POST",token:"owner-user",body:{pairingToken,expectedFingerprint:fingerprint},
    });
    assert.equal(reused.status,404);
    const strangerDevices=await request("/v1/devices",{token:"other-user"});
    assert.deepEqual(strangerDevices.data.devices,[]);
    async function signed(path,body,method="POST"){
      const raw=method==="GET"?Buffer.alloc(0):Buffer.from(JSON.stringify(body));
      const proof=deviceHeaders(keys.privateKeyPem,{
        deviceId,method,path,rawBody:raw,
      });
      const response=await fetch(url+path,{method,
        headers:{...proof,...(method==="POST"?{"content-type":"application/json"}:{})},
        ...(method==="POST"?{body:raw}:{})});
      return {status:response.status,data:await response.json()};
    }
    const caps=await signed("/v1/device/capabilities",
      {capabilities:["workspace_inventory"]});
    assert.equal(caps.status,200);
    assert.equal((await signed("/v1/device/heartbeat",{})).status,200);
    const unavailable=await request("/v1/runs",{
      method:"POST",token:"other-user",headers:{"idempotency-key":randomUUID()},
      body:{deviceId,kind:"workspace_inventory",mode:"read_only"},
    });
    assert.equal(unavailable.status,409);
    const requested=await request("/v1/runs",{
      method:"POST",token:"owner-user",headers:{"idempotency-key":randomUUID()},
      body:{deviceId,kind:"workspace_inventory",mode:"read_only"},
    });
    assert.equal(requested.status,201,JSON.stringify(requested.data));
    const approvalId=requested.data.approvalId;
    assert.equal((await signed("/v1/device/claim",{})).data.run,null,
      "No execution before exact owner approval");
    const decision=await request("/v1/approvals/"+approvalId+"/decision",{
      method:"POST",token:"owner-user",body:{approve:true,
        expectedActionHash:requested.data.actionHash},
    });
    assert.equal(decision.status,200,JSON.stringify(decision.data));
    const repeat=await request("/v1/approvals/"+approvalId+"/decision",{
      method:"POST",token:"owner-user",body:{approve:true,
        expectedActionHash:requested.data.actionHash},
    });
    assert.equal(repeat.status,409);
    const claimed=await signed("/v1/device/claim",{});
    assert.equal(claimed.status,200);
    assert.equal(claimed.data.run.id,requested.data.runId);
    const events=await signed("/v1/device/runs/"+requested.data.runId+"/events",{
      leaseToken:claimed.data.run.leaseToken,kind:"status",text:"Workspace ready",
    });
    assert.equal(events.status,201);
    const history=await request("/v1/runs/"+requested.data.runId+"/events?after=0",
      {token:"owner-user"});
    assert.equal(history.status,200);
    assert.equal(history.data.events[0].text,"Workspace ready");
    const otherHistory=await request("/v1/runs/"+requested.data.runId+"/events?after=0",
      {token:"other-user"});
    assert.equal(otherHistory.status,404);
    const done=await signed("/v1/device/runs/"+requested.data.runId+"/complete",{
      leaseToken:claimed.data.run.leaseToken,ok:true,result:{verified:true},
    });
    assert.equal(done.status,200);
    const actual=await request("/v1/runs/"+requested.data.runId,{token:"owner-user"});
    assert.equal(actual.data.status,"completed");
    assert.deepEqual(actual.data.result,{verified:true});
    const revoked=await request("/v1/devices/"+deviceId+"/revoke",{
      method:"POST",token:"owner-user",body:{},
    });
    assert.equal(revoked.status,200);
    assert.equal((await signed("/v1/device/heartbeat",{})).status,401);
  }finally{
    if(app)await app.close();
    if(pool)await pool.end();
    await admin.end();
  }
});
