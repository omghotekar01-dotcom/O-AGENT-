import test from "node:test";
import assert from "node:assert/strict";
import {createRun} from "../src/operations.mjs";

const deviceId="11111111-1111-4111-8111-111111111111";
const tenantId="22222222-2222-4222-8222-222222222222";
const runId="33333333-3333-4333-8333-333333333333";
const cwd="/trusted/project";
const requestKey="unique-request-key-123456789";

function database() {
  const calls=[];
  const client={
    async query(sql,params=[]) {
      calls.push({sql,params});
      if(sql.includes("SELECT capabilities,workspace_root FROM devices"))
        return {rows:[{capabilities:[
          "workspace_inventory","claude_agent_turn","copilot_sdk_turn",
        ],workspace_root:"/trusted"}],rowCount:1};
      if(sql.includes("SELECT count(*) FILTER"))
        return {rows:[{pending:0,daily:0}],rowCount:1};
      if(sql.includes("INSERT INTO runs("))
        return {rows:[{id:runId}],rowCount:1};
      return {rows:[],rowCount:0};
    },
  };
  return {client,calls};
}
function payload(kind="claude_agent_turn",mode="read_only") {
  return {deviceId,kind,mode,prompt:"Continue the existing task and explain results",
    cwd:kind==="workspace_inventory"?"":cwd};
}
function queries(calls,fragment) {
  return calls.filter(({sql})=>sql.includes(fragment));
}

test("verified owner read-only agent prompt queues immediately, without echoing its text for approval",async()=>{
  const {client,calls}=database();
  const result=await createRun(client,tenantId,"owner",payload(),requestKey,
    {ownerInitiated:true});
  assert.equal(result.status,"queued");
  assert.equal(result.ownerAuthorized,true);
  assert.match(result.runId,/^[0-9a-f-]{36}$/);
  assert.equal(queries(calls,"INSERT INTO approvals").length,0);
  const insert=queries(calls,"INSERT INTO runs(")[0];
  assert.match(insert.sql,/'queued'/);
  assert.equal(insert.params[5],"Continue the existing task and explain results");
  const audit=queries(calls,"INSERT INTO audit_events")[0];
  assert.equal(audit.params[3],result.runId);
  assert.equal(audit.params[2],"run.owner_readonly_queued");
});

test("workspace operator cannot bypass owner approval even with read-only mode",async()=>{
  const {client,calls}=database();
  const result=await createRun(client,tenantId,"operator",payload(),
    requestKey,{ownerInitiated:false});
  assert.equal(result.status,"waiting_for_approval");
  assert.equal(result.ownerAuthorized,undefined);
  assert.equal(queries(calls,"INSERT INTO approvals").length,1);
  assert.match(queries(calls,"INSERT INTO runs(")[0].sql,/'waiting_for_approval'/);
});

test("owner workspace-writing request requires approval, including SDK tools",async()=>{
  const {client,calls}=database();
  const result=await createRun(client,tenantId,"owner",
    payload("copilot_sdk_turn","workspace_write"),requestKey,
    {ownerInitiated:true});
  assert.equal(result.status,"waiting_for_approval");
  assert.equal(queries(calls,"INSERT INTO approvals").length,1);
});

test("owner read-only diagnostic cannot bypass the inventory approval",async()=>{
  const {client,calls}=database();
  const result=await createRun(client,tenantId,"owner",
    payload("workspace_inventory","read_only"),requestKey,
    {ownerInitiated:true});
  assert.equal(result.status,"waiting_for_approval");
  assert.equal(queries(calls,"INSERT INTO approvals").length,1);
});

test("unverified, offline and missing-capability workers remain blocked before a write",async()=>{
  const {client,calls}=database();
  await assert.rejects(createRun(client,tenantId,"owner",
    payload("codex_cli_turn"),requestKey,{ownerInitiated:true}),
    {status:400});
  assert.equal(queries(calls,"INSERT INTO runs(").length,0);
});
