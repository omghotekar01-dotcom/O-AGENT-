import test from "node:test";
import assert from "node:assert/strict";
import {checkPilot,formatDoctor} from "../../../deploy/saas/free-pilot/doctor.mjs";

const origin="https://laptop.example.ts.net";
const secretNames=["OAGENT_RUNTIME_PASSWORD","OAGENT_MIGRATION_PASSWORD",
  "OAGENT_KEYCLOAK_ADMIN_PASSWORD","OAGENT_OWNER_PASSWORD",
  "OAGENT_VAPID_PUBLIC_KEY"];
const secrets="OAGENT_ORIGIN="+origin+"\n"+
  secretNames.map(x=>x+"="+"a".repeat(40)).join("\n")+"\n";
const fakeDocker=(command,args)=>{
  if(command==="docker"&&args[0]==="compose")return "Docker Compose v2";
  if(command==="tailscale")return JSON.stringify({BackendState:"Running",
    Self:{DNSName:"laptop.example.ts.net."}});
  throw Error("Unexpected command");
};
const fakeFetch=async url=>{
  if(url.endsWith("/health/ready"))
    return Response.json({status:"ready",database:"connected"});
  if(url.endsWith("/.well-known/openid-configuration"))
    return Response.json({issuer:origin+"/auth/realms/oagent",
      authorization_endpoint:origin+"/auth/realms/oagent/protocol/openid-connect/auth",
      jwks_uri:origin+"/auth/realms/oagent/protocol/openid-connect/certs"});
  if(url.endsWith("/v1/public-config"))
    return Response.json({authEnabled:true,clientId:"oagent-web",redirectUri:origin+"/"});
  throw Error("Unexpected URL "+url);
};
test("free-pilot doctor checks real prerequisites without revealing credentials",async()=>{
  const r=await checkPilot({execute:fakeDocker,
    read:async()=>secrets,statFile:async()=>({mode:0o100600}),
    fetchImpl:fakeFetch,nodeVersion:"22.13.0"});
  assert.equal(r.ready,true,JSON.stringify(r.checks));
  assert.equal(r.checks.length,7);
  const message=formatDoctor(r);
  assert.match(message,/Private pilot prerequisites/);
  assert.doesNotMatch(message,/a{20}|password:|PRIVATE KEY/);
});
test("doctor provides actionable errors on missing infrastructure and does not fabricate readiness",async()=>{
  const r=await checkPilot({
    execute:()=>{throw Error("secret error detail never displayed");},
    read:async()=>{throw Error("TOKEN-SECRET-NOT-LOGGED");},
    statFile:async()=>({mode:0o100777}),
    fetchImpl:async()=>{throw Error("hidden network credentials");},
    nodeVersion:"18.0.0",
  });
  assert.equal(r.ready,false);
  assert.ok(r.checks.filter(x=>!x.ok).length>=5);
  assert.match(formatDoctor(r),/Docker Desktop/);
  assert.doesNotMatch(JSON.stringify(r),/TOKEN-SECRET|hidden network credentials/);
});
test("doctor rejects a hostname mismatch and incorrect OAuth issuer",async()=>{
  const r=await checkPilot({execute:fakeDocker,
    read:async()=>secrets.replace(origin,"https://other.example.ts.net"),
    statFile:async()=>({mode:0o100600}),
    fetchImpl:fakeFetch,nodeVersion:"22.13.0"});
  assert.equal(r.ready,false);
  assert.equal(r.checks.find(x=>x.name==="Tailscale connection").ok,false);
  assert.equal(r.checks.find(x=>x.name==="OIDC identity provider").ok,false);
});
