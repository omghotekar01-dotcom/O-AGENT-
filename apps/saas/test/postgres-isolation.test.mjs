import test from "node:test";
import assert from "node:assert/strict";
import {randomUUID} from "node:crypto";
import {Pool} from "pg";
import {migrate,withIdentity,withTenant,audit,assertTenantDatabaseSecurity,pruneEphemeralAuthenticationData} from "../src/store.mjs";
import {startEnrollment,inspectEnrollment,enrollmentStatus,approveEnrollment,listDevices,revokeDevice,updateCapabilities,
  heartbeat,createRun,listRuns,runDetail,listApprovals,decideApproval,claimRun,
  finishRun,requestToolApproval,toolApprovalStatus,cancelRun,
  resolveInterruptedRun,listAuditEvents,deleteOwnAccount} from "../src/operations.mjs";
import {generateDeviceKeys,sha256,deviceHeaders,verifyDeviceHeaders} from "../src/device-crypto.mjs";
import {registerPush,unregisterPush,pushStatus,notifyTenant} from "../src/push.mjs";
import {exportOwnerData} from "../src/export.mjs";

test("PostgreSQL enforces tenant isolation, signed device enrollment and one-time approvals",
  {timeout:45000,skip:!process.env.OAGENT_TEST_DATABASE_URL},async()=>{
    const admin=new Pool({connectionString:process.env.OAGENT_TEST_DATABASE_URL});
    try {
      await migrate(admin);
      await migrate(admin); // Idempotent, immutable migrations are not replayed.
      const versions=await admin.query(
        "SELECT name,length(checksum) AS length FROM schema_migrations ORDER BY name");
      assert.deepEqual(versions.rows.map(x=>x.name),
        ["001_init.sql","002_legacy_upgrade.sql","003_team_workspaces.sql"]);
      assert.ok(versions.rows.every(x=>x.length===64));
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
        await assert.rejects(()=>assertTenantDatabaseSecurity(
          {query:async sql=>sql.includes("pg_roles")?
            {rows:[{rolsuper:false,rolbypassrls:false}],rowCount:1}:
            {rows:[{relname:"runs"}],rowCount:1}}),
          /owner of tenant tables/);

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
        const review=await withIdentity(pool,owner,c=>
          inspectEnrollment(c,pairing.pairingToken));
        assert.equal(review.name,"Test laptop");
        assert.match(review.fingerprint,/^[0-9a-f]{24}$/);
        await assert.rejects(()=>withIdentity(pool,owner,(c,t)=>
          approveEnrollment(c,t,owner.subject,pairing.pairingToken,
            "incorrect-fingerprint")),/identity changed/);
        const device=await withIdentity(pool,owner,(c,t)=>
          approveEnrollment(c,t,owner.subject,pairing.pairingToken,
            review.fingerprint));
        assert.deepEqual(await enrollmentStatus(pool,pairing.pairingToken),
          {approved:true,deviceId:device.deviceId});
        await assert.rejects(()=>withIdentity(pool,owner,(c,t)=>
          approveEnrollment(c,t,owner.subject,pairing.pairingToken,
            review.fingerprint)),/expired or already used/);
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
          await updateCapabilities(c,tenantA,device.deviceId,["claude_agent_turn"],"/work");
          await heartbeat(c,device.deviceId);
        });
        await assert.rejects(()=>withIdentity(pool,owner,(c,t)=>createRun(
          c,t,owner.subject,{deviceId:device.deviceId,
            kind:"claude_agent_turn",mode:"read_only",
            prompt:"Should reject external directory",cwd:"/private/other"},
          randomUUID()+"_bad")),/outside the enrolled workspace/);
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
        const tool=await withTenant(pool,tenantA,(c,t)=>
          requestToolApproval(c,t,device.deviceId,run.runId,{
            leaseToken:claimed.run.leaseToken,requestId:"native-permission-123",
            description:"Edit test file inside enrolled project",
          }));
        const actionable=await withIdentity(pool,owner,c=>listApprovals(c));
        assert.equal(actionable.length,1);
        assert.equal(actionable[0].actionable,true);
        await assert.rejects(()=>withTenant(pool,tenantA,(c,t)=>
          finishRun(c,t,device.deviceId,run.runId,{
            leaseToken:claimed.run.leaseToken,ok:true,result:{message:"should refuse"},
          })),/tool permission is unresolved/);
        await withIdentity(pool,owner,(c,t)=>decideApproval(c,t,owner.subject,
          tool.approvalId,{approve:true,expectedActionHash:tool.actionHash}));
        assert.equal((await withTenant(pool,tenantA,c=>
          toolApprovalStatus(c,device.deviceId,tool.approvalId))).state,"approved");
        const finished=await withTenant(pool,tenantA,(c,t)=>
          finishRun(c,t,device.deviceId,run.runId,{
            leaseToken:claimed.run.leaseToken,ok:true,result:{message:"real"},
          }));
        assert.equal(finished.status,"completed");
        assert.equal((await withIdentity(pool,owner,c=>
          runDetail(c,run.runId))).status,"completed");
        const exported=await withIdentity(pool,owner,c=>exportOwnerData(c,owner));
        assert.equal(exported.format,"oagent-tenant-export-v1");
        assert.ok(exported.runs.some(x=>x.id===run.runId));
        assert.ok(exported.audit.some(x=>x.action==="run.completed"));
        assert.ok(!JSON.stringify(exported).includes("PRIVATE KEY"));
        const strangerExport=await withIdentity(pool,stranger,c=>
          exportOwnerData(c,stranger));
        assert.equal(strangerExport.runs.length,0);
        assert.equal(strangerExport.devices.length,0);
        const subscription={endpoint:"https://fcm.googleapis.com/fcm/send/"+
          "a".repeat(60),keys:{auth:"A".repeat(22),p256dh:"B".repeat(87)}};
        await withIdentity(pool,owner,(c,t)=>registerPush(c,t,subscription));
        assert.equal((await withIdentity(pool,owner,pushStatus)).subscribedDevices,1);
        assert.equal((await withIdentity(pool,stranger,pushStatus)).subscribedDevices,0);
        let sentTo=[];
        const notify=await notifyTenant(pool,tenantA,{
          publicOrigin:"https://laptop.tail.ts.net",
          push:{publicKey:"P".repeat(87),privateKey:"S".repeat(43)},
        },{send:async(sub,payload)=>{
          sentTo.push({sub,payload});return {statusCode:201};
        }});
        assert.equal(notify.sent,1);
        assert.equal(sentTo[0].sub.endpoint,subscription.endpoint);
        assert.doesNotMatch(sentTo[0].payload,/test file|Explain this test/);
        await assert.rejects(()=>withIdentity(pool,owner,(c,t)=>registerPush(
          c,t,{...subscription,endpoint:"https://127.0.0.1/internal"})),
          /Invalid push subscription|Unsupported browser push service/);
        await assert.rejects(()=>withIdentity(pool,stranger,(c,t)=>
          registerPush(c,t,subscription)),error=>
          error.status===409&&/another account/.test(error.message));
        await withIdentity(pool,owner,c=>unregisterPush(c,subscription.endpoint));
        assert.equal((await withIdentity(pool,owner,pushStatus)).subscribedDevices,0);
        const pending=await withIdentity(pool,owner,(c,t)=>
          createRun(c,t,owner.subject,payload,randomUUID()+"_pending"));
        assert.equal((await withIdentity(pool,owner,(c,t)=>
          cancelRun(c,t,owner.subject,pending.runId))).status,"cancelled");
        const interrupted=await withIdentity(pool,owner,(c,t)=>
          createRun(c,t,owner.subject,payload,randomUUID()+"_recover"));
        await withIdentity(pool,owner,(c,t)=>decideApproval(c,t,owner.subject,
          interrupted.approvalId,{approve:true,
            expectedActionHash:interrupted.actionHash}));
        const claimedInterrupted=await withTenant(pool,tenantA,(c,t)=>
          claimRun(c,t,device.deviceId));
        assert.equal(claimedInterrupted.run.id,interrupted.runId);
        await withTenant(pool,tenantA,c=>c.query(
          "UPDATE runs SET lease_expires_at=now()-interval '1 minute' WHERE id=$1",
          [interrupted.runId]));
        const halted=await withTenant(pool,tenantA,(c,t)=>
          claimRun(c,t,device.deviceId));
        assert.equal(halted.reason,"needs_recovery");
        assert.equal(halted.run,null);
        await assert.rejects(()=>withIdentity(pool,owner,(c,t)=>
          resolveInterruptedRun(c,t,owner.subject,interrupted.runId,
            {confirm:"REPLAY_AUTOMATICALLY"})),/confirmation required/);
        const recovered=await withIdentity(pool,owner,(c,t)=>
          resolveInterruptedRun(c,t,owner.subject,interrupted.runId,
            {confirm:"MARK_INTERRUPTED_RUN_FAILED"}));
        assert.deepEqual(recovered,{runId:interrupted.runId,
          status:"failed",replayed:false});
        const staleNonce="expired-"+randomUUID();
        await admin.query(
          "INSERT INTO device_replay_nonces(device_id,nonce,expires_at) VALUES($1,$2,now()-interval '1 minute')",
          [device.deviceId,staleNonce]);
        const stalePair=await startEnrollment(pool,{
          name:"Expired test pairing",publicKeyPem:keys.publicKeyPem,
        },sha256("expired-source-"+randomUUID()));
        await admin.query(
          "UPDATE pending_devices SET expires_at=now()-interval '1 minute' WHERE token_hash=$1",
          [sha256(stalePair.pairingToken)]);
        const pruned=await pruneEphemeralAuthenticationData(pool);
        assert.ok(pruned.expiredNonces>=1);
        assert.ok(pruned.expiredEnrollmentRequests>=1);
        const retained=await admin.query(
          "SELECT count(*)::int AS count FROM device_replay_nonces WHERE nonce=$1",
          [staleNonce]);
        assert.equal(retained.rows[0].count,0);
        const direct=await pool.query("SELECT count(*)::int AS count FROM runs");
        assert.equal(direct.rows[0].count,0,
          "FORCE RLS without a scoped transaction denies all tenant runs");
        const pendingOnRevoke=await withIdentity(pool,owner,(c,t)=>
          createRun(c,t,owner.subject,payload,randomUUID()+"_revoke"));
        const auditsBefore=await withIdentity(pool,owner,c=>listAuditEvents(c));
        assert.ok(auditsBefore.some(x=>x.action==="run.requested"));
        assert.equal((await withIdentity(pool,stranger,c=>listAuditEvents(c)))
          .some(x=>x.target_id===pendingOnRevoke.runId),false);
        await withIdentity(pool,owner,(c,t)=>revokeDevice(
          c,t,owner.subject,device.deviceId));
        assert.equal((await withIdentity(pool,owner,c=>
          runDetail(c,pendingOnRevoke.runId))).status,"cancelled");
        assert.ok(!(await withIdentity(pool,owner,c=>listApprovals(c)))
          .some(x=>x.run_id===pendingOnRevoke.runId));
        const replay=deviceHeaders(keys.privateKeyPem,{
          deviceId:device.deviceId,method:"POST",path:"/v1/device/heartbeat",
          rawBody:Buffer.from("{}"),
        });
        await assert.rejects(()=>verifyDeviceHeaders(pool,{
          headers:replay,method:"POST",path:"/v1/device/heartbeat",
          rawBody:Buffer.from("{}"),
        }),/Device authentication failed/);
        await assert.rejects(()=>withIdentity(pool,owner,(c,t)=>
          deleteOwnAccount(c,t,owner.subject,{
            confirmation:"DELETE",acknowledgeLocalData:true,
          })),/typed confirmation/);
        assert.equal((await withIdentity(pool,owner,(c,t)=>
          deleteOwnAccount(c,t,owner.subject,{
            confirmation:"DELETE_MY_OAGENT_WORKSPACE",
            acknowledgeLocalData:true,
          }))).deleted,true);
        assert.equal((await admin.query(
          "SELECT count(*)::int AS n FROM identities WHERE tenant_id=$1",
          [tenantA])).rows[0].n,0);
        assert.equal((await admin.query(
          "SELECT count(*)::int AS n FROM device_auth_keys WHERE device_id=$1",
          [device.deviceId])).rows[0].n,0);
        assert.equal((await withIdentity(pool,stranger,(_c,t)=>t)),tenantB);
        assert.notEqual((await withIdentity(pool,owner,(_c,t)=>t)),tenantA);
      }finally{await pool.end();}
    }finally{await admin.end();}
});
