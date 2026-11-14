// CI-ONLY! The production realm disables resource-owner-password grants.
// This tests the exact OIDC issuer, scoped access token, audience and API.
// It is never enabled in the shipped server or browser and never logs secrets.
import http from "node:http";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import {dirname,join} from "node:path";
import {fileURLToPath} from "node:url";

if(process.env.CI!=="true" ||
   process.env.OAGENT_CI_ALLOW_PASSWORD_GRANT!=="1")
  throw Error("CI-only synthetic identity test is not enabled");

const file=join(dirname(fileURLToPath(import.meta.url)),".env.local");
const data=await readFile(file,"utf8");
const secret=data.match(/^OAGENT_OWNER_PASSWORD=([A-Za-z0-9_-]{20,})$/m)?.[1];
if(!secret)throw Error("Missing ephemeral CI-only login credential");
const host="ci-runner.example.ts.net";
function request(path,{method="GET",body,authorization}={}){
  return new Promise((resolve,reject)=>{
    const headers={Host:host,Accept:"application/json"};
    const payload=body?Buffer.from(body.toString()):null;
    if(payload){
      headers["Content-Type"]="application/x-www-form-urlencoded";
      headers["Content-Length"]=String(payload.byteLength);
    }
    if(authorization)headers.Authorization="Bearer "+authorization;
    const req=http.request({hostname:"127.0.0.1",port:8791,path,
      method,headers,timeout:7000},response=>{
      const chunks=[];
      response.on("data",part=>chunks.push(part));
      response.on("end",()=>{
        let json={};
        try{json=JSON.parse(Buffer.concat(chunks).toString("utf8"));}
        catch{}
        resolve({status:response.statusCode,body:json});
      });
    });
    req.on("error",()=>reject(Error("Local integration network error")));
    req.on("timeout",()=>req.destroy(Error("Identity integration timed out")));
    req.end(payload);
  });
}
const form=new URLSearchParams({
  grant_type:"password",client_id:"oagent-web",username:"pilot-owner",
  password:secret,scope:"openid profile oagent:read oagent:operate",
});
const token=await request(
  "/auth/realms/oagent/protocol/openid-connect/token",
  {method:"POST",body:form});
assert.equal(token.status,200,"Synthetic CI owner token exchange failed");
assert.equal(typeof token.body.access_token,"string");
assert.ok(token.body.access_token.length>100);
const scopes=new Set((token.body.scope||"").split(" "));
assert.ok(scopes.has("oagent:read"),"OIDC read scope missing");
assert.ok(scopes.has("oagent:operate"),"OIDC operate scope missing");
const access=token.body.access_token;
const me=await request("/v1/me",{authorization:access});
assert.equal(me.status,200,"OIDC access token was not accepted by O-AGENT API");
assert.match(me.body.tenantId,/^[0-9a-f-]{36}$/);
const audit=await request("/v1/audit",{authorization:access});
assert.equal(audit.status,200,"Tenant-scoped audit API rejected genuine OIDC token");
assert.ok(Array.isArray(audit.body.events));
const approvals=await request("/v1/approvals",{authorization:access});
assert.equal(approvals.status,200);
const forbidden=await request("/v1/account/delete",{method:"POST",
  authorization:access,body:new URLSearchParams({})});
assert.equal(forbidden.status,415,"Erasure must require JSON and typed confirmation");
const outsider=await request("/v1/me");
assert.equal(outsider.status,401);
console.log("CI Keycloak→OIDC→signed JWT audience/scope→tenant API integration passed; no credentials or tokens printed.");
