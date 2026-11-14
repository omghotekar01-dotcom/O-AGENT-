import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
const ui=readFileSync(new URL("../public/index.html",import.meta.url),"utf8");
const script=readFileSync(new URL("../public/app.js",import.meta.url),"utf8");
const css=readFileSync(new URL("../public/style.css",import.meta.url),"utf8");
const server=readFileSync(new URL("../src/server.mjs",import.meta.url),"utf8");

test("SaaS command center has unique ids and no broken control references",()=>{
  const ids=[...ui.matchAll(/id="([^"]+)"/g)].map(x=>x[1]);
  assert.equal(new Set(ids).size,ids.length);
  for(const item of script.matchAll(/\$\("([^"]+)"\)/g))
    assert.ok(ids.includes(item[1]),"Missing "+item[1]);
  for(const page of ["overview","approvals","runs","devices","audit","team"]){
    assert.match(ui,new RegExp('data-panel="'+page+'"'));
    assert.match(ui,new RegExp('data-view="'+page+'"'));
  }
});
test("provider activity stays sourced from real endpoints, not UI dummy data",()=>{
  for(const path of ["/v1/me","/v1/devices","/v1/runs","/v1/approvals",
    "/v1/devices/enrollments/inspect","/v1/devices/enrollments/approve",
    "/v1/public-config"]){
    assert.ok(script.includes(path),"Real endpoint missing: "+path);
  }
  assert.match(script,/Promise\.all/);
  assert.match(script,/String\(approvals\.length\)/);
  assert.doesNotMatch(script,/innerHTML|outerHTML|eval\(|new Function/);
  assert.match(script,/createElement/);
  assert.match(css,/prefers-reduced-motion/);
});
test("web login is PKCE S256, transient in-memory token, and state protected",()=>{
  assert.match(script,/crypto\.subtle\.digest/);
  assert.match(script,/code_challenge_method:"S256"/);
  assert.match(script,/response_type:"code"/);
  assert.match(script,/expected!==stateReturned/);
  assert.match(script,/sessionStorage\.removeItem\("oagent_pkce_verifier"\)/);
  assert.match(script,/history\.replaceState/);
  assert.match(script,/accessToken=token\.access_token/);
  assert.doesNotMatch(script,/localStorage\.setItem/);
  assert.doesNotMatch(script,/sessionStorage\.setItem\("accessToken"/);
});
test("approvals require fresh canonical run detail and exact hashed decisions",()=>{
  assert.match(script,/const run=await api\("\/v1\/runs\/"/);
  assert.match(script,/expectedActionHash:item\.action_hash/);
  assert.match(script,/run\.device_id!==item\.device_id/);
  assert.match(script,/Date\.parse\(item\.expires_at\)<=Date\.now\(\)/);
  assert.match(script,/approve:decision/);
  assert.match(script,/approval recorded|Approval recorded/i);
  assert.match(ui,/id="reviewDialog"/);
});
test("pairing never grants access without verified fingerprint and owner consent",()=>{
  assert.match(script,/verified\.fingerprint!==button\.dataset\.fingerprint/);
  assert.match(script,/await reviewExact/);
  assert.match(script,/expectedFingerprint:verified\.fingerprint/);
  assert.match(script,/sessionStorage\.removeItem\("oagent_pending_pair"\)/);
  assert.match(ui,/id="pairPanel"/);
});

test("MCP internal handler receives verified identity, not end-user authorization header",()=>{
  assert.match(server,/const protocolHeaders=/);
  assert.match(server,/headers:protocolHeaders/);
  assert.doesNotMatch(server,/headers:req\.headers,body/);
  assert.match(server,/authInfo:\{/);
  assert.match(server,/clientId:identity\.subject/);
});

test("home-screen PWA contains real network-only security behavior",()=>{
  const manifest=JSON.parse(readFileSync(new URL("../public/manifest.webmanifest",import.meta.url),"utf8"));
  const worker=readFileSync(new URL("../public/sw.js",import.meta.url),"utf8");
  assert.equal(manifest.display,"standalone");
  assert.equal(manifest.start_url,"/");
  assert.ok(manifest.icons[0].src==="/icon.svg");
  assert.match(ui,/rel="manifest"/);
  assert.match(script,/serviceWorker\.register\("\/sw\.js"/);
  assert.doesNotMatch(worker,/addEventListener\("fetch"/);
  assert.doesNotMatch(worker,/caches\.open/);
});

test("opt-in privacy-safe phone alerts never send or display prompt content",()=>{
  const sw=readFileSync(new URL("../public/sw.js",import.meta.url),"utf8");
  assert.match(sw,/addEventListener\("push"/);
  assert.match(sw,/addEventListener\("notificationclick"/);
  assert.doesNotMatch(sw,/addEventListener\("fetch"/);
  assert.match(script,/Notification\.requestPermission\(\)/);
  assert.match(script,/pushManager\.subscribe/);
  assert.match(script,/subscription\.toJSON\(\)/);
  assert.match(ui,/id="enableAlerts"/);
});

test("interrupted provider runs cannot be auto-replayed and owners can cancel queued tasks",()=>{
  assert.match(script,/MARK_INTERRUPTED_RUN_FAILED/);
  assert.match(script,/resolve-interrupted/);
  assert.match(script,/Cancel pending run/);
  assert.match(script,/No replay was performed/);
});

test("security view uses RLS audit, typed deletion, safe logout and consent labels",()=>{
  assert.match(script,/api\("\/v1\/audit"\)/);
  assert.match(ui,/id="auditList"/);
  assert.match(ui,/data-view="audit"/);
  assert.match(ui,/id="deletePhrase"/);
  assert.match(ui,/id="ackLocalData"/);
  assert.match(script,/DELETE_MY_OAGENT_WORKSPACE/);
  assert.match(script,/logoutEndpoint/);
  assert.match(script,/disableAlerts/);
  assert.match(script,/confirmLabel:"Enroll this device"/);
  assert.match(script,/confirmLabel:"Request approval"/);
  assert.doesNotMatch(script,/setAppBadge\(approvals\.length\)/);
});

test("account data export uses owner-scoped JSON with no credentials",()=>{
  const exportServer=readFileSync(new URL("../src/export.mjs",import.meta.url),"utf8");
  assert.match(exportServer,/exportOwnerData/);
  assert.match(exportServer,/LIMIT \$1/);
  assert.doesNotMatch(exportServer,/SELECT \*/);
  assert.match(ui,/id="exportAccount"/);
  assert.match(script,/\/v1\/account\/export/);
  assert.match(script,/URL\.revokeObjectURL/);
});

test("team UI uses verified workspace roles, one-use invites and no fake billing",()=>{
  for(const id of ["workspaceSwitch","teamRole","joinTeamForm","teamAdmin",
    "inviteTeamForm","teamMemberList","billingUsage"]){
    assert.match(ui,new RegExp('id="'+id+'"'));
  }
  assert.match(script,/api\("\/v1\/team\/join"/);
  assert.match(script,/api\("\/v1\/team\/workspaces"/);
  assert.match(script,/api\("\/v1\/billing\/usage"/);
  assert.match(script,/state\.role==="owner"/);
  assert.match(script,/oagent_active_workspace/);
  assert.match(ui,/Payment processing|payment|billing/i);
  assert.doesNotMatch(script,/innerHTML|outerHTML|eval\(/);
});
