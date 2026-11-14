import test from "node:test";
import assert from "node:assert/strict";
import {randomUUID} from "node:crypto";
import {Pool} from "pg";
import {migrate,withIdentity,withTenant,audit,assertTenantDatabaseSecurity} from "../src/store.mjs";
import {startEnrollment,approveEnrollment,listDevices,revokeDevice,updateCapabilities,
  heartbeat,createRun,listRuns,runDetail,listApprovals,decideApproval,claimRun,
  finishRun} from "../src/operations.mjs";
import {generateDeviceKeys,sha256,deviceHeaders,verifyDeviceHeaders} from "../src/device-crypto.mjs";

test("PostgreSQL enforces tenant isolation, signed device enrollment and one-time approvals",
  {timeout:45000,skip:!process.env.OAGENT_TEST_DATABASE_URL},async()=>{
    const admin=new Pool({connectionString:process.env.OAGENT_TEST_DATABASE_URL});
    try {
      await migrate(admin);
      await admin.query("DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='oagent_test_runtime') THEN CREATE ROLE oagent_test_runtime LOGIN PASSWORD 'temporary-testing-password' NOSUPERUSER NOBYPASSRLS; END IF; END $$");
      await admin.query("GRANT USAGE ON SCHEMA public TO oagent_test_runtime");
      await admin.query("GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA public TO oagent_test_runtime");
      await admin.query("GRANT USAGE,SELECT ON ALL SEQUENCES IN SCHEMA public TO oagent_test_runtime");
      const url=new URL(process.env.OAGENT_TEST_DATABASE_URL);
      url.username="oagent_test_runtime";url.password="temporary-testing-password";
      const pool=new Pool({connectionString:url.toString()});
      try{
        await assert.rejects(()=>assertTenantDatabaseSecurity(admin),/Unsafe PostgreSQL runtime role/);
        assert.deepEqual(await assertTenantDatabaseSecurity(pool),{ok:true});
        const owner={issuer:"https://issuer.test/",subject:"owner-"+randomUUID()};
        const stranger={issuer:owner.issuer,subject:"stranger-"+randomUUID()};
        const tenantA=await withIdentity(pool,owner,async(client,tenant)=>{
          await audit(client,tenant,owner.subject,"test.created",null);
          return tenant;
        });
        const tenantB=await withIdentity(pool,stranger,async(_client,tenant)=>tenant);
        assert.notEqual(tenantA,tenantB);
        const keys=generateDeviceKeys();
        const pairing=await startEnrollment(pool,{
          name:"Test laptop",publicKeyPem:keys.publicKeyPem,
        },sha256("test-ip-"+randomUUID()));
        const device=await withIdentity(pool,owner,(c,t)=>
          approveEnrollment(c,t,owner.subject,pairing.pairingToken));
        assert.ok(device.deviceId);
        await assert.rejects(()=>withIdentity(pool,stranger,(c,t)=>
          revokeDevice(c,t,stranger.subject,device.deviceId)),/Device not found/);
        assert.equal((await withIdentity(pool,stranger,listDevices)).length,0);
        const raw=Buffer.from('{"capabilities":["claude_agent_turn"]}');
        const signed=deviceHeaders(keys.privateKeyPem,{
          deviceId:device.deviceId,method:"POST",path:"/v1/device/capabilities",rawBody:raw,
        });
        const auth=await verifyDeviceHeaders(pool,{
          headers:signed,method:"POST",path:"/v1/device/capabilities",rawBody:raw,
        });
        assert.equal(auth.tenantId,tenantA);
        await assert.rejects(()=>verifyDeviceHeaders(pool,{
          headers:signed,method:"POST",path:"/v1/device/capabilities",rawBody:raw,
        }),/Device authentication failed/);
        await withTenant(pool,tenantA,async c=>{
          await updateCapabilities(c,tenantA,device.deviceId,["claude_agent_turn"]);
          await heartbeat(c,device.deviceId);
        });
        const key=randomUUID()+"_user";
        const payload={deviceId:device.deviceId,kind:"claude_agent_turn",
          mode:"read_only",prompt:"Explain this test",cwd:"/work/example"};
        const run=await withIdentity(pool,owner,(c,t)=>
          createRun(c,t,owner.subject,payload,key));
        assert.equal(run.status,"waiting_for_approval");
        assert.equal((await withIdentity(pool,stranger,listRuns)).length,0);
        assert.equal((await withIdentity(pool,stranger,listApprovals)).length,0);
        await assert.rejects(()=>withIdentity(pool,stranger,c=>
          runDetail(c,run.runId)),/Run not found/);
        await assert.rejects(()=>withIdentity(pool,stranger,(c,t)=>
          decideApproval(c,t,stranger.subject,run.approvalId,{
            approve:true,expectedActionHash:run.actionHash,
          })),/Approval expired/);
        await assert.rejects(()=>withIdentity(pool,owner,(c,t)=>
          decideApproval(c,t,owner.subject,run.approvalId,{
            approve:true,expectedActionHash:"f".repeat(64),
          })),/Approval expired/);
        await withIdentity(pool,owner,(c,t)=>decideApproval(c,t,owner.subject,
          run.approvalId,{approve:true,expectedActionHash:run.actionHash}));
        await assert.rejects(()=>withIdentity(pool,owner,(c,t)=>
          decideApproval(c,t,owner.subject,run.approvalId,{
            approve:true,expectedActionHash:run.actionHash,
          })),/Approval expired/);
        const claimed=await withTenant(pool,tenantA,(c,t)=>
          claimRun(c,t,device.deviceId));
        assert.equal(claimed.run.id,run.runId);
        assert.equal((await withTenant(pool,tenantA,(c,t)=>
          claimRun(c,t,device.deviceId))).run,null);
        await assert.rejects(()=>withTenant(pool,tenantA,(c,t)=>
          finishRun(c,t,device.deviceId,run.runId,{
            leaseToken:randomUUID(),ok:true,result:{message:"bad"},
          })),/lease expired/);
        const finished=await withTenant(pool,tenantA,(c,t)=>
          finishRun(c,t,device.deviceId,run.runId,{
            leaseToken:claimed.run.leaseToken,ok:true,result:{message:"real"},
          }));
        assert.equal(finished.status,"completed");
        assert.equal((await withIdentity(pool,owner,c=>
          runDetail(c,run.runId))).status,"completed");
        const direct=await pool.query("SELECT count(*)::int AS count FROM runs");
        assert.equal(direct.rows[0].count,0,
          "FORCE RLS without a scoped transaction denies all tenant runs");
        await withIdentity(pool,owner,(c,t)=>revokeDevice(
          c,t,owner.subject,device.deviceId));
        const replay=deviceHeaders(keys.privateKeyPem,{
          deviceId:device.deviceId,method:"POST",path:"/v1/device/heartbeat",
          rawBody:Buffer.from("{}"),
        });
        await assert.rejects(()=>verifyDeviceHeaders(pool,{
          headers:replay,method:"POST",path:"/v1/device/heartbeat",
          rawBody:Buffer.from("{}"),
        }),/Device authentication failed/);
      }finally{await pool.end();}
    }finally{await admin.end();}
});
