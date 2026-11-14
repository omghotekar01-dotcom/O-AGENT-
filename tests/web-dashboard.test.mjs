import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
const html=readFileSync(new URL("../apps/control-plane/public/index.html",import.meta.url),"utf8");
const js=readFileSync(new URL("../apps/control-plane/public/dashboard.js",import.meta.url),"utf8");
const css=readFileSync(new URL("../apps/control-plane/public/dashboard.css",import.meta.url),"utf8");

test("web workspace has no broken ID references or inert section links",()=>{
  const ids=[...html.matchAll(/id="([^"]+)"/g)].map(m=>m[1]);
  assert.equal(new Set(ids).size,ids.length,"All UI IDs must be unique");
  for(const match of js.matchAll(/\$\("([^"]+)"\)/g)){
    assert.ok(ids.includes(match[1]),"JS references missing element #"+match[1]);
  }
  const views=[...html.matchAll(/data-panel="([^"]+)"/g)].map(m=>m[1]);
  assert.deepEqual(views,["overview","files","desktop","activity","integrations","setup"]);
  for(const view of views)
    assert.match(html,new RegExp('data-view="'+view+'"'),"Missing navigation for "+view);
});

test("dashboard protects credentials and renders untrusted source as text",()=>{
  assert.doesNotMatch(js,/(innerHTML|outerHTML|eval\()/);
  assert.match(js,/sessionStorage\.setItem\("oagent_token"/);
  assert.match(js,/sessionStorage\.removeItem\("oagent_token"/);
  assert.match(js,/authorization:"Bearer "\+token/);
  assert.match(js,/textContent=String\(text\)/);
  assert.match(html,/id="fileEditor"[^>]*readonly/);
  assert.match(html,/id="confirmDialog"/);
  assert.match(html,/id="inputDialog"/);
  assert.match(css,/\[hidden\]\{display:none!important\}/);
  assert.match(html,/id="desktopTrackpad"/);
  assert.match(html,/id="desktopPairCode"/);
  assert.match(html,/id="desktopActivate"/);
  assert.match(html,/id="desktopChooseScreen"/);
  assert.match(js,/api\("\/api\/input\/activate"/);
  assert.match(js,/navigator\.mediaDevices\.getDisplayMedia/);
  assert.match(js,/status===429/);
  assert.match(js,/type:"tap"/);
  assert.match(html,/id="desktopImageFile"/);
  assert.match(js,/fetch\("\/api\/input\/image"/);
  assert.doesNotMatch(js,/innerHTML=/);
  assert.match(html,/id="desktopStopInput"/);
  assert.match(js,/api\("\/api\/input\/pair"/);
  assert.match(js,/api\("\/api\/input\/action"/);
  assert.match(js,/api\("\/api\/screen\/stop"/);
  assert.match(js,/\/api\/screen\/frame\?after=/);
  assert.match(js,/desktopQueue\.length=0/);
  assert.doesNotMatch(js,/new WebSocket\(/);
  assert.match(css,/touch-action:none/);
});

test("connected tool statuses remain backend-derived, not fabricated",()=>{
  assert.match(js,/api\("\/api\/integrations"\)/);
  assert.match(js,/api\("\/api\/vscode\/workspaces"\)/);
  assert.match(js,/api\("\/api\/state"\)/);
  assert.match(js,/api\("\/api\/projects"\)/);
});

test("web action inbox uses authenticated exact-request review and never fakes empty state",()=>{
  assert.match(html,/id="approvalInboxList"/);
  assert.match(html,/id="approvalInboxCount"/);
  assert.match(html,/id="refreshApprovals"/);
  assert.match(js,/api\("\/api\/remote\/overview"\)/);
  assert.match(js,/async function reviewInboxDecision/);
  assert.match(js,/const task=await api\(path\)/);
  assert.match(js,/item\.state!=="pending"/);
  assert.match(js,/await confirmAction\("Review exact "/);
  assert.match(js,/ownerOverview\.error\?"Unavailable"/);
  assert.doesNotMatch(js,/Approve this exact task\?/);
  assert.match(css,/approval-inbox/);
});
