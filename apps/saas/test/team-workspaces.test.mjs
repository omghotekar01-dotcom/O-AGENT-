import test from "node:test";
import assert from "node:assert/strict";
import {randomUUID} from "node:crypto";
import pg from "pg";
import {migrate} from "../src/store.mjs";
import {makeSaasServer} from "../src/server.mjs";

test("real PostgreSQL: OIDC team roles, one-time invites, selected workspaces and account safety",
  {timeout:45000,skip:!process.env.OAGENT_TEST_DATABASE_URL},async()=>{
  const admin=new pg.Pool({connectionString:process.env.OAGENT_TEST_DATABASE_URL});
  let pool,app;
  try{
    await migrate(admin);
    await admin.query("DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='oagent_team_test') THEN CREATE ROLE oagent_team_test LOGIN PASSWORD 'ci-only-team-password' NOSUPERUSER NOBYPASSRLS; END IF; END $$");
    await admin.query("GRANT USAGE ON SCHEMA public TO oagent_team_test");
    await admin.query("GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA public TO oagent_team_test");
    await admin.query("GRANT USAGE,SELECT ON ALL SEQUENCES IN SCHEMA public TO oagent_team_test");
    const db=new URL(process.env.OAGENT_TEST_DATABASE_URL);
    db.username="oagent_team_test";db.password="ci-only-team-password";
    pool=new pg.Pool({connectionString:db.href});
    const subjects={
      owner:"team-owner-"+randomUUID(),
      viewer:"team-viewer-"+randomUUID(),
      operator:"team-operator-"+randomUUID(),
    };
    const config={publicOrigin:"http://127.0.0.1",issuer:"https://team.test/",
      audience:"oagent-api",clientIds:["test"],webAuth:null};
    const authenticate=async(header)=>{
      const key=String(header||"").replace(/^Bearer /,"");
      if(!Object.hasOwn(subjects,key))
        throw Object.assign(Error("Unauthenticated"),{status:401});
      return {issuer:config.issuer,subject:subjects[key],
        scopes:new Set(["oagent-read","oagent-operate"]),expiresAt:Date.now()+60000};
    };
    app=makeSaasServer({config,pool,authenticate});
    await new Promise(ok=>app.server.listen(0,"127.0.0.1",ok));
    config.publicOrigin="http://127.0.0.1:"+app.server.address().port;
    async function call(path,{actor="owner",method="GET",body,workspace}={}){
      const res=await fetch(config.publicOrigin+path,{method,headers:{
        authorization:"Bearer "+actor,
        ...(workspace?{"x-oagent-workspace":workspace}:{}),
        ...(body?{"content-type":"application/json"}:{})
      },...(body?{body:JSON.stringify(body)}:{})});
      return {status:res.status,data:await res.json()};
    }
    const owner=await call("/v1/me");
    assert.equal(owner.status,200);
    assert.equal(owner.data.role,"owner");
    const home=owner.data.tenantId;
    const billing=await call("/v1/billing/usage");
    assert.equal(billing.status,200);
    assert.equal(billing.data.billingStatus,"not_configured");
    assert.equal(billing.data.paidSubscriptionActive,false);
    assert.equal(billing.data.providerCostsSeparate,true);
    assert.equal(billing.data.usage.requests_this_month,0);
    const rename=await call("/v1/team/settings",{
      method:"POST",body:{name:"Engineering squad"}});
    assert.equal(rename.status,200);
    assert.equal((await call("/v1/team/invites",{
      method:"POST",body:{role:"owner"}})).status,400);
    const invite=await call("/v1/team/invites",{
      method:"POST",body:{role:"viewer"}});
    assert.equal(invite.status,201,JSON.stringify(invite.data));
    assert.match(invite.data.inviteToken,/^oti_[A-Za-z0-9_-]{43}$/);
    assert.equal((await call("/v1/team/members",{actor:"viewer"})).status,403);
    const join=await call("/v1/team/join",{
      actor:"viewer",method:"POST",body:{inviteToken:invite.data.inviteToken}});
    assert.equal(join.status,200,JSON.stringify(join.data));
    assert.equal(join.data.workspaceId,home);
    assert.equal((await call("/v1/team/join",{
      actor:"operator",method:"POST",body:{inviteToken:invite.data.inviteToken}})).status,409,
      "A used invitation cannot be reused by another signed-in subject");
    const privateHome=await call("/v1/me",{actor:"viewer"});
    assert.equal(privateHome.status,200);
    assert.notEqual(privateHome.data.tenantId,home);
    assert.equal(privateHome.data.role,"owner");
    const selected=await call("/v1/me",{actor:"viewer",workspace:home});
    assert.equal(selected.status,200);
    assert.equal(selected.data.role,"viewer");
    assert.equal((await call("/v1/billing/usage",{actor:"viewer",workspace:home})).status,403);
    const workspaces=await call("/v1/team/workspaces",{actor:"viewer"});
    assert.equal(workspaces.status,200);
    assert.ok(workspaces.data.workspaces.some(x=>x.tenant_id===home&&x.role==="viewer"));
    assert.ok(workspaces.data.workspaces.some(x=>x.tenant_id===privateHome.data.tenantId&&x.role==="owner"));
    assert.equal((await call("/v1/devices",{
      actor:"viewer",workspace:home})).status,200);
    assert.equal((await call("/v1/runs",{
      actor:"viewer",workspace:home,method:"POST",body:{}})).status,403);
    assert.equal((await call("/v1/team/invites",{
      actor:"viewer",workspace:home,method:"POST",body:{role:"viewer"}})).status,403);
    const opInvite=await call("/v1/team/invites",{
      method:"POST",body:{role:"operator"}});
    assert.equal(opInvite.status,201);
    assert.equal((await call("/v1/team/join",{
      actor:"operator",method:"POST",body:{inviteToken:opInvite.data.inviteToken}})).status,200);
    assert.equal((await call("/v1/me",{
      actor:"operator",workspace:home})).data.role,"operator");
    assert.equal((await call("/v1/runs",{
      actor:"operator",workspace:home,method:"POST",body:{}})).status,400,
      "Operator passes role gate and reaches request input validation");
    const other=(await call("/v1/me",{actor:"viewer"})).data.tenantId;
    assert.equal((await call("/v1/me",{
      actor:"owner",workspace:other})).status,403,
      "Tenant ID is not an authorization capability");
    assert.equal((await call("/v1/account/delete",{method:"POST",body:{
      confirmation:"DELETE_MY_OAGENT_WORKSPACE",acknowledgeLocalData:true}})).status,409);
    const members=await call("/v1/team/members");
    assert.equal(members.status,200);
    assert.equal(members.data.members.length,3);
    assert.equal((await call("/v1/team/members/remove",{
      method:"POST",body:{issuer:config.issuer,subject:subjects.owner}})).status,403,
      "Owner cannot remove themselves");
    assert.equal((await call("/v1/team/members/remove",{
      method:"POST",body:{issuer:config.issuer,subject:subjects.viewer}})).status,200);
    assert.equal((await call("/v1/me",{
      actor:"viewer",workspace:home})).status,403);
    assert.equal((await call("/v1/team/members/remove",{
      method:"POST",body:{issuer:config.issuer,subject:subjects.operator}})).status,200);
    assert.equal((await call("/v1/account/delete",{method:"POST",body:{
      confirmation:"DELETE_MY_OAGENT_WORKSPACE",acknowledgeLocalData:true}})).status,200);
  }finally{
    if(app)await app.close();
    if(pool)await pool.end();
    await admin.end();
  }
});
