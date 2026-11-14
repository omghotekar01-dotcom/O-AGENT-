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
  assert.deepEqual(views,["overview","files","activity","integrations","setup"]);
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
});

test("connected tool statuses remain backend-derived, not fabricated",()=>{
  assert.match(js,/api\("\/api\/integrations"\)/);
  assert.match(js,/api\("\/api\/vscode\/workspaces"\)/);
  assert.match(js,/api\("\/api\/state"\)/);
  assert.match(js,/api\("\/api\/projects"\)/);
});
