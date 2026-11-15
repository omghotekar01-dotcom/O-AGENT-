import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {nativeClientFromTemplate,validateNativeClient,
  MOBILE_CLIENT_ID,MOBILE_CALLBACK} from "../../../deploy/saas/free-pilot/ensure-native-client.mjs";
const read=p=>readFileSync(new URL("../../../"+p,import.meta.url),"utf8");
test("mobile OAuth client has exact deep-link, required PKCE and audience",()=>{
  const realm=JSON.parse(read("deploy/saas/free-pilot/oagent-realm.json"));
  const client=nativeClientFromTemplate(realm);
  assert.equal(client.clientId,MOBILE_CLIENT_ID);
  assert.equal(client.redirectUris[0],MOBILE_CALLBACK);
  assert.deepEqual(client.webOrigins,[]);
  assert.equal(client.attributes["pkce.code.challenge.method"],"S256");
  assert.deepEqual(client.defaultClientScopes.includes("oagent-operate"),true);
  assert.equal(client.protocolMappers.some(x=>
    x.config?.["included.custom.audience"]==="oagent-api"),true);
  assert.equal(validateNativeClient(client),true);
  assert.throws(()=>validateNativeClient({...client,
    directAccessGrantsEnabled:true}),/secure native/);
  assert.throws(()=>validateNativeClient({...client,
    redirectUris:["https://malicious.invalid/"]}),/secure native/);
});
test("native client only on private local pilot API allowlist",()=>{
  const compose=read("deploy/saas/free-pilot/compose.yaml");
  assert.equal(compose.split("OAGENT_OIDC_CLIENT_IDS: oagent-web,oagent-mobile").length,3);
  // The single entrypoint delegates to the safety-checked one-click orchestrator.
  assert.match(read("START-O-AGENT.cmd"),/scripts\\\\one-click-pilot[.]mjs/);
  const launcher=read("scripts/one-click-pilot.mjs");
  assert.match(launcher,/register=ensureNativeClient/);
  assert.match(launcher,/await register\\(\\)/);
  assert.match(launcher,/if\\(!outcome\\?\\.ready\\)/);

  assert.match(read("REPAIR-O-AGENT.cmd"),/node ensure-native-client[.]mjs/);
});
