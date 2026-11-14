import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {tailnetOrigin,renderOwnerRealm} from "../../../deploy/saas/free-pilot/setup.mjs";
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

test("free pilot exposes a single private start command, never Funnel",()=>{
  const program=read("start.mjs");
  assert.match(program,/startFreePilot/);
  assert.match(program,/127\.0\.0\.1:8791/);
  assert.doesNotMatch(program,/run\("tailscale",\["funnel"/);
});

test("gateway strips upstream file capabilities instead of removing security sandboxing",()=>{
  const compose=read("compose.yaml");
  const dockerfile=read("Dockerfile.gateway");
  assert.match(compose,/dockerfile: deploy\/saas\/free-pilot\/Dockerfile.gateway/);
  assert.match(compose,/cap_drop: \["ALL"\]/);
  assert.match(compose,/no-new-privileges:true/);
  assert.match(dockerfile,/setcap -r \/usr\/bin\/caddy/);
  assert.match(dockerfile,/EXPOSE 8081/);
});

test("Keycloak private realm has exact sign-out redirect",()=>{
  const realm=JSON.parse(read("oagent-realm.json"));
  const web=realm.clients.find(x=>x.clientId==="oagent-web");
  assert.equal(web.attributes["post.logout.redirect.uris"],"$"+"{OAGENT_ORIGIN}/");
  assert.match(read("compose.yaml"),/OAGENT_OIDC_LOGOUT_URL:/);
});

test("private realm renderer inserts generated owner password and HTTPS redirects",()=>{
  const template=JSON.parse(read("oagent-realm.json"));
  const origin="https://laptop.example.ts.net",password="a".repeat(48);
  const realm=renderOwnerRealm(template,{origin,password});
  assert.equal(realm.users[0].credentials[0].value,password);
  assert.equal(realm.clients[0].redirectUris[0],origin+"/");
  assert.equal(realm.clients[0].webOrigins[0],origin);
  assert.equal(realm.clients[0].directAccessGrantsEnabled,false);
  assert.ok(!JSON.stringify(realm).includes("$"+"{OAGENT_"));
  const compose=read("compose.yaml");
  assert.match(compose,/\.private\/oagent-realm\.json:\/opt\/keycloak/);
});

test("one-shot private realm copy stays isolated and readable only by Keycloak uid",()=>{
  const compose=read("compose.yaml");
  assert.match(compose,/realm-init:\n    image: busybox:1\.37/);
  assert.match(compose,/network_mode: none/);
  assert.match(compose,/cap_add: \["CHOWN"\]/);
  assert.match(compose,/chown 1000:0 \/out\/oagent-realm\.json/);
  assert.match(compose,/chmod 0400 \/out\/oagent-realm\.json/);
  assert.match(compose,/pilot_realm:\/opt\/keycloak\/data\/import:ro/);
  assert.doesNotMatch(compose,/\.private\/oagent-realm\.json:\/opt\/keycloak/);
});
