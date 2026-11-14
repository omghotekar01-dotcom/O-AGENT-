import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {tailnetOrigin} from "../../..//deploy/saas/free-pilot/setup.mjs";
import {readSaasConfig} from "../src/config.mjs";

const read=name=>readFileSync(new URL("../../../deploy/saas/free-pilot/"+name,import.meta.url),"utf8");
test("pilot setup requires a real, connected Tailscale HTTPS DNS name",()=>{
  const fake=()=>JSON.stringify({BackendState:"Running",Self:{DNSName:"laptop.my-tailnet.ts.net."}});
  assert.equal(tailnetOrigin({},fake),"https://laptop.my-tailnet.ts.net");
  assert.throws(()=>tailnetOrigin({OAGENT_TAILNET_HOST:"public.example.com"}),/MagicDNS/);
  assert.throws(()=>tailnetOrigin({},()=>JSON.stringify({BackendState:"Stopped"})),/connected/);
  assert.throws(()=>tailnetOrigin({},()=>{throw Error("absent")}),/Install Tailscale/);
});
test("only precise Docker-private pilot DB/JWKS exceptions are accepted",()=>{
  const valid={
    NODE_ENV:"production",OAGENT_LOCAL_PILOT:"1",
    OAGENT_SAAS_ORIGIN:"https://laptop.my-tailnet.ts.net",
    OAGENT_OIDC_ISSUER:"https://laptop.my-tailnet.ts.net/auth/realms/oagent",
    OAGENT_OIDC_JWKS_URL:"http://identity:8080/auth/realms/oagent/protocol/openid-connect/certs",
    OAGENT_OIDC_AUDIENCE:"oagent-api",OAGENT_OIDC_CLIENT_IDS:"oagent-web",
    DATABASE_URL:"postgresql://runtime:secret@db:5432/oagent?sslmode=disable",
  };
  const config=readSaasConfig(valid);
  assert.equal(config.localPilot,true);
  assert.match(config.jwksUrl,/^http:\/\/identity:8080/);
  assert.throws(()=>readSaasConfig({...valid,
    OAGENT_SAAS_ORIGIN:"https://example.com"}),/Private pilot/);
  assert.throws(()=>readSaasConfig({...valid,
    DATABASE_URL:"postgres://runtime:secret@evil.com/oagent?sslmode=disable"}),/sslmode=verify-full/);
  assert.throws(()=>readSaasConfig({...valid,
    OAGENT_OIDC_JWKS_URL:"http://evil.com/keys"}),/secure origin/);
});
test("self-host stack never publishes identity or postgres ports",()=>{
  const compose=read("compose.yaml");
  const realm=JSON.parse(read("oagent-realm.json"));
  const init=read("init-postgres.sh");
  assert.equal((compose.match(/ports:/g)||[]).length,1);
  assert.match(compose,/127\.0\.0\.1:8791:8081/);
  assert.match(compose,/OAGENT_LOCAL_PILOT: "1"/);
  assert.match(compose,/postgres:16-alpine/);
  assert.match(compose,/keycloak:26\.4\.0/);
  assert.equal(realm.registrationAllowed,false);
  assert.equal(realm.clients[0].attributes["pkce.code.challenge.method"],"S256");
  assert.equal(realm.clients[0].publicClient,true);
  assert.equal(realm.clients[0].implicitFlowEnabled,false);
  assert.equal(realm.clients[0].directAccessGrantsEnabled,false);
  assert.match(init,/NOBYPASSRLS/);
  assert.match(init,/ALTER DEFAULT PRIVILEGES/);
});

test("native Web Push VAPID keys are EC-P256, generated locally without a paid vendor",()=>{
  const script=read("setup.mjs");
  assert.match(script,/generateKeyPairSync\("ec"/);
  assert.match(script,/OAGENT_VAPID_PUBLIC_KEY/);
  assert.match(script,/OAGENT_VAPID_PRIVATE_KEY/);
});
