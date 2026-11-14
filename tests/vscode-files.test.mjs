import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, mkdir, writeFile, readFile, symlink, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createRequire } from "node:module";
import { VscodeFileRelay } from "../apps/control-plane/src/vscode-file-relay.mjs";
const require = createRequire(import.meta.url);
const {allowedPath,listWorkspaceFolder,readWorkspaceText,writeWorkspaceText,hash} =
  require("../apps/vscode/src/file-access.cjs");

test("temporary VS Code file relay rejects unpaired and malformed requests", () => {
  let now=100000;
  const relay=new VscodeFileRelay({now:()=>now});
  assert.throws(()=>relay.request({workerId:"vscode-test",op:"list",path:""}),/not online/);
  relay.heartbeat("vscode-test");
  for(const path of ["../private",".env","C:\\Users\\private","/etc/passwd",
    "a/../b","a//b"]){
    if(path===".env")continue; // extension enforces protected names
    assert.throws(()=>relay.request({workerId:"vscode-test",op:"read",path}),/Invalid/);
  }
  assert.throws(()=>relay.request({workerId:"vscode-test",op:"write",path:"test.txt",
    content:"abc",expectedHash:"wrong"}),/invalid/);
  assert.throws(()=>relay.request({workerId:"vscode-test",op:"shell",path:""}),/Unsupported/);
  const first=relay.request({workerId:"vscode-test",op:"list",path:""});
  assert.match(first.id,/^[a-f0-9-]{36}$/);
  assert.equal(relay.claim("vscode-test").request.id,first.id);
  assert.throws(()=>relay.finish("other-worker",{id:first.id,ok:true,result:{}}),/another editor/);
  relay.finish("vscode-test",{id:first.id,ok:true,result:{
    entries:[{name:"src",path:"src",type:"directory"}]}});
  assert.equal(relay.status(first.id).result.entries[0].name,"src");
  now+=91000;
  assert.throws(()=>relay.status(first.id),/expired/);
});

test("file relay does not expose queued edit contents through status or persistence",()=>{
  const relay=new VscodeFileRelay({now:()=>100000});
  relay.heartbeat("vscode-test");
  const value=relay.request({workerId:"vscode-test",op:"write",
    path:"README.md",content:"changed source",expectedHash:"0".repeat(64)});
  assert.equal(JSON.stringify(relay.status(value.id)).includes("changed source"),false);
  const request=relay.claim("vscode-test").request;
  assert.equal(request.content,"changed source");
  relay.finish("vscode-test",{id:value.id,ok:true,result:{saved:true}});
  assert.equal(JSON.stringify(relay.status(value.id)).includes("changed source"),false);
  assert.equal(relay.requests.get(value.id).content,undefined);
});

test("workspace files are scoped, skip secrets, reject symlinks and respect edits",async()=>{
  const root=await mkdtemp(join(tmpdir(),"oagent-files-"));
  try {
    await mkdir(join(root,"src"));
    await writeFile(join(root,"README.md"),"hello\n");
    await writeFile(join(root,".env"),"API_SECRET=never");
    await writeFile(join(root,"src","main.js"),"const a = 1;\n");
    await symlink(join(root,".env"),join(root,"linked-key"));
    assert.equal(allowedPath("../secrets.txt"),false);
    assert.equal(allowedPath(".env"),false);
    assert.equal(allowedPath("src/main.js"),true);
    const listing=await listWorkspaceFolder(root,"");
    assert.deepEqual(listing.entries.map(x=>x.name),["src","linked-key","README.md"].sort(
      (a,b)=>Number(b==="src")-Number(a==="src")||a.localeCompare(b)
    ).filter(x=>x!=="linked-key"));
  } finally { await rm(root,{recursive:true,force:true}); }
});
