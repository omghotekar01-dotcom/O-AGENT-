import test from "node:test";
import assert from "node:assert/strict";
import {randomUUID} from "node:crypto";
import {createOidcVerifier} from "../src/oidc.mjs";
import {readSaasConfig} from "../src/config.mjs";
import {canonicalRequest,deviceHeaders,generateDeviceKeys,parseEd25519PublicKey,
  verifyDeviceHeaders} from "../src/device-crypto.mjs";

const config={
  issuer:"https://id.example.com/",jwksUrl:"https://id.example.com/.well-known/jwks.json",
  audience:"oagent-api",clientIds:["mobile-prod","mcp-client"],
};
test("SaaS config fails closed without HTTPS, explicit OIDC and database",()=>{
  assert.throws(()=>readSaasConfig({}),/OAGENT_SAAS_ORIGIN/);
  const env={NODE_ENV:"production",
    OAGENT_SAAS_ORIGIN:"http://untrusted.example",
    OAGENT_OIDC_ISSUER:"https://id.example.com",
    OAGENT_OIDC_JWKS_URL:"https://id.example.com/jwks",
    OAGENT_OIDC_AUDIENCE:"oagent-api",OAGENT_OIDC_CLIENT_IDS:"mobile-prod",
    DATABASE_URL:"postgres://user:pass@localhost/db"};
  assert.throws(()=>readSaasConfig(env),/secure origin/);
  env.OAGENT_SAAS_ORIGIN="https://app.example.com";
  env.DATABASE_URL="postgres://user:pass@localhost/db?sslmode=disable";
  assert.throws(()=>readSaasConfig(env),/sslmode=verify-full/);
  env.DATABASE_URL="postgres://user:pass@localhost/db?sslmode=verify-full";
  assert.equal(readSaasConfig(env).publicOrigin,"https://app.example.com");
  assert.equal(readSaasConfig(env).issuer,"https://id.example.com");
  const login={
    ...env,OAGENT_OIDC_WEB_CLIENT_ID:"mobile-prod",
    OAGENT_OIDC_AUTHORIZE_URL:"https://id.example.com/auth",
    OAGENT_OIDC_TOKEN_URL:"https://id.example.com/token",
    OAGENT_OIDC_LOGOUT_URL:"https://id.example.com/logout",
  };
  assert.equal(readSaasConfig(login).webAuth.logoutEndpoint,
    "https://id.example.com/logout");
  assert.throws(()=>readSaasConfig({...login,
    OAGENT_OIDC_LOGOUT_URL:"https://unexpected.example/logout"}),
    /match the authorization server/);
  assert.throws(()=>readSaasConfig({...env,
    OAGENT_OIDC_LOGOUT_URL:"https://id.example.com/logout"}),
    /Configure all three/);
  assert.throws(()=>readSaasConfig({...env,OAGENT_LOCAL_PILOT:"1"}),
    /Private pilot requires/);
  assert.throws(()=>readSaasConfig({...env,DATABASE_URL:
    "postgres://user:pass@db/oagent?sslmode=disable"}),
    /sslmode=verify-full/);

});
test("OIDC validates issuer/audience/algorithms/client audience and scopes",async()=>{
  let options;
  const verifier=createOidcVerifier(config,{
    jwksFactory:()=>({}),
    verify:async(_token,_keys,opts)=>{
      options=opts;
      return {payload:{sub:"oidc-user-a",azp:"mobile-prod",scope:"oagent-read",
        exp:1770000000,email_verified:true}};
    },
  });
  const token="Bearer "+"x".repeat(70);
  const user=await verifier(token);
  assert.equal(user.subject,"oidc-user-a");
  assert.equal(options.issuer,config.issuer);
  assert.equal(options.audience,config.audience);
  assert.deepEqual(options.algorithms,["RS256","ES256","PS256"]);
  await assert.rejects(()=>verifier(token,"oagent-operate"),/Insufficient/);
  await assert.rejects(()=>verifier("Bearer short"),/invalid bearer/);
  const invalid=createOidcVerifier(config,{
    jwksFactory:()=>({}),
    verify:async()=>({payload:{sub:"someone",azp:"other-client",scope:"oagent-read"}}),
  });
  await assert.rejects(()=>invalid(token),/not authorized/);
});
test("per-device Ed25519 signature binds method, path, body and timestamp",()=>{
  const {publicKeyPem,privateKeyPem}=generateDeviceKeys();
  const parsed=parseEd25519PublicKey(publicKeyPem);
  assert.ok(parsed.length>30);
  const id=randomUUID();
  const signed=deviceHeaders(privateKeyPem,{
    deviceId:id,method:"POST",path:"/v1/device/heartbeat",rawBody:Buffer.from("{}"),
    now:()=>1700000000000,nonce:"A".repeat(32),
  });
  assert.equal(signed["x-oagent-device-id"],id);
  const message=canonicalRequest({method:"POST",path:"/v1/device/heartbeat",
    rawBody:Buffer.from("{}"),timestamp:1700000000000,nonce:"A".repeat(32)});
  assert.ok(message.toString().includes("oagent-device-v1"));
  assert.throws(()=>parseEd25519PublicKey("not a key"),/Invalid/);
  assert.notEqual(signed["x-oagent-signature"],deviceHeaders(privateKeyPem,{
    deviceId:id,method:"POST",path:"/v1/device/other",
    rawBody:Buffer.from("{}"),now:()=>1700000000000,
    nonce:"A".repeat(32),
  })["x-oagent-signature"]);
});
test("database-backed replay nonce rejects duplicates and stale device tokens",async()=>{
  const {publicKeyPem,privateKeyPem}=generateDeviceKeys();
  const key=parseEd25519PublicKey(publicKeyPem),id=randomUUID(),tenant=randomUUID();
  let inserts=0;
  const pool={query:async sql=>{
    if(sql.includes("FROM device_auth_keys"))
      return {rows:[{device_id:id,tenant_id:tenant,public_key:key}]};
    if(sql.includes("INSERT INTO device_replay_nonces"))
      return {rowCount:inserts++===0?1:0};
    throw Error("Unexpected SQL");
  }};
  const rawBody=Buffer.from('{"ok":true}'),path="/v1/device/heartbeat";
  const headers=deviceHeaders(privateKeyPem,{
    deviceId:id,method:"POST",path,rawBody,now:()=>1700000000000,
  });
  const body={headers,method:"POST",path,rawBody,now:()=>1700000000000};
  assert.equal((await verifyDeviceHeaders(pool,body)).tenantId,tenant);
  await assert.rejects(()=>verifyDeviceHeaders(pool,body),/authentication failed/);
  await assert.rejects(()=>verifyDeviceHeaders(pool,{...body,rawBody:Buffer.from("{}")}),
    /authentication failed/);
  await assert.rejects(()=>verifyDeviceHeaders(pool,{...body,now:()=>1700000500000}),
    /authentication failed/);
});
