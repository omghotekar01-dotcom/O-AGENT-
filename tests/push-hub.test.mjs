import test from "node:test";
import assert from "node:assert/strict";
import { generateKeyPairSync } from "node:crypto";
import { ControlPlane } from "../apps/control-plane/src/core.mjs";
import { PushHub } from "../apps/control-plane/src/push-hub.mjs";

const {privateKey}=generateKeyPairSync("rsa",{modulusLength:2048,
  privateKeyEncoding:{type:"pkcs8",format:"pem"},
  publicKeyEncoding:{type:"spki",format:"pem"}});
const config=Buffer.from(JSON.stringify({
  project_id:"oagent-dev-demo",
  client_email:"tester@oagent-dev-demo.iam.gserviceaccount.com",
  private_key:privateKey,
})).toString("base64");
const validToken="device-test-token-"+"z".repeat(120);
function fixture(enabled=true) {
  const core=new ControlPlane();
  const delivered=[];
  const accounts={
    master:Buffer.alloc(32),
    encrypt:(userId,provider,secret)=>({wrapped:Buffer.from(
      userId+"|"+provider+"|"+secret).toString("base64")}),
    decrypt:(userId,provider,record)=>{
      const [owner,scope,...parts]=Buffer.from(record.wrapped,"base64")
        .toString("utf8").split("|");
      assert.equal(owner,userId);assert.equal(scope,provider);
      return parts.join("|");
    },
  };
  const fetchImpl=async(url,init)=>{
    if(url==="https://oauth2.googleapis.com/token"){
      assert.equal(init.method,"POST");
      return {ok:true,json:async()=>({access_token:"demo-access-token-with-valid-length",
        expires_in:3600})};
    }
    assert.equal(url,"https://fcm.googleapis.com/v1/projects/oagent-dev-demo/messages:send");
    delivered.push(JSON.parse(init.body));
    return {ok:true,json:async()=>({name:"test-message"})};
  };
  const hub=new PushHub(core,accounts,{fetchImpl,env: enabled
    ? {OAGENT_FCM_SERVICE_ACCOUNT_BASE64:config}:{ }});
  return {core,hub,delivered};
}
test("push stays off without backend service-account and never registers device",()=>{
  const {hub}=fixture(false);
  assert.equal(hub.status("owner").configured,false);
  assert.throws(()=>hub.register("owner",{platform:"android",token:validToken}),
    /need a configured Firebase/);
});
test("push registration is account-isolated and revocable, no tokens in public responses",()=>{
  const {core,hub}=fixture();
  const state=hub.register("owner",{platform:"android",token:validToken,label:"My phone"});
  assert.equal(state.devices.length,1);
  assert.equal(state.devices[0].label,"My phone");
  assert.doesNotMatch(JSON.stringify(state),/device-test-token/);
  assert.equal(hub.status("member-2").devices.length,0);
  assert.equal(hub.register("owner",{platform:"android",token:validToken}).devices.length,1);
  assert.ok(core.data.accounts.pushDevices.owner[0].secret.wrapped);
  assert.throws(()=>hub.register("member-2",{platform:"linux",token:validToken}),
    /Unsupported push platform/);
  hub.unregister("owner",state.devices[0].id);
  assert.equal(hub.status("owner").devices.length,0);
  assert.throws(()=>hub.unregister("owner",state.devices[0].id),/not found/);
});
test("FCM sends minimal, non-sensitive approval update and exact owner-only routing",async()=>{
  const {hub,delivered}=fixture();
  hub.register("owner",{platform:"android",token:validToken});
  const memberToken="member-token-"+"p".repeat(110);
  hub.register("member-2",{platform:"ios",token:memberToken});
  await hub._dispatch({type:"task.waiting_for_approval",
    taskId:"task-approval-123",prompt:"PASSWORD=do-not-transmit",
    cwd:"C:\\Private\\secrets"});
  assert.equal(delivered.length,1);
  assert.equal(delivered[0].message.token,validToken);
  assert.equal(delivered[0].message.data.type,"approval");
  assert.equal(delivered[0].message.data.taskId,"task-approval-123");
  assert.doesNotMatch(JSON.stringify(delivered),/PASSWORD|Private|secrets/);
  delivered.length=0;
  await hub._dispatch({type:"account.cursor.created",userId:"member-2"});
  assert.equal(delivered.length,1);
  assert.equal(delivered[0].message.token,memberToken);
  assert.equal(delivered[0].message.data.type,"update");
});
