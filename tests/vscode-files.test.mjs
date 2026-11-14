import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, mkdir, writeFile, readFile, symlink, rm, stat, rename as renameOnDisk } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createRequire } from "node:module";
import { VscodeFileRelay } from "../apps/control-plane/src/vscode-file-relay.mjs";
const require = createRequire(import.meta.url);
const {allowedPath,listWorkspaceFolder,readWorkspaceText,writeWorkspaceText,
  createWorkspaceText,renameWorkspaceFile,deleteWorkspaceFile,hash} =
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

test("source viewer and editor save only the expected unchanged file",async()=>{
  const root=await mkdtemp(join(tmpdir(),"oagent-edit-"));
  const filename=join(root,"README.md");
  try {
    await writeFile(filename,"hello\n");
    let value="hello\n";
    let dirty=false;
    const uri={fsPath:filename};
    const doc={
      uri,languageId:"markdown",
      getText:()=>value, get isDirty(){return dirty;},
      positionAt:() => ({line:1,character:0}),
      save:async()=>{await writeFile(filename,value);dirty=false;return true;},
    };
    class WorkspaceEdit {
      replace(_uri,_range,text) {this.next=text;}
    }
    class Range {constructor(_from,_to) {}}
    class Position {constructor(line,character) {this.line=line;this.character=character;}}
    const vscode={
      Uri:{file:()=>uri},WorkspaceEdit,Range,Position,
      workspace:{
        openTextDocument:async()=>doc,
        applyEdit:async(edit)=>{value=edit.next;dirty=true;return true;},
      }
    };
    const opened=await readWorkspaceText(root,"README.md",vscode);
    assert.equal(opened.content,"hello\n");
    assert.equal(opened.readOnly,false);
    await assert.rejects(()=>writeWorkspaceText(root,"README.md","changed","0".repeat(64),vscode),/changed/);
    const saved=await writeWorkspaceText(root,"README.md","changed\n",hash("hello\n"),vscode);
    assert.equal(saved.saved,true);
    assert.equal(await readFile(filename,"utf8"),"changed\n");
    dirty=true;
    await assert.rejects(()=>writeWorkspaceText(root,"README.md","again",hash("changed\n"),vscode),/unsaved/);
    await assert.rejects(()=>readWorkspaceText(root,".env",vscode),/Protected/);
    await assert.rejects(()=>readWorkspaceText(root,"missing.txt",vscode),/ENOENT/);
  } finally { await rm(root,{recursive:true,force:true}); }
});

test("file relay requires version hash and refuses protected destinations", () => {
  const relay=new VscodeFileRelay({now:()=>100000});
  relay.heartbeat("vscode-test");
  assert.throws(()=>relay.request({workerId:"vscode-test",op:"rename",
    path:"readme.md",newPath:"../secrets.txt",expectedHash:"0".repeat(64)}),/Invalid/);
  assert.throws(()=>relay.request({workerId:"vscode-test",op:"delete",
    path:"readme.md"}),/hash/);
  assert.throws(()=>relay.request({workerId:"vscode-test",op:"rename",
    path:"readme.md",newPath:"readme.md",expectedHash:"0".repeat(64)}),/different/);
  assert.throws(()=>relay.request({workerId:"vscode-test",op:"create",
    path:"hello.txt",content:"".padEnd(48001,"a")}),/48,000/);
  const newFile=relay.request({workerId:"vscode-test",op:"create",
    path:"hello.txt",content:"private draft"});
  assert.doesNotMatch(JSON.stringify(relay.status(newFile.id)),/private draft/);
  const claimed=relay.claim("vscode-test");
  assert.equal(claimed.request.content,"private draft");
  relay.finish("vscode-test",{id:newFile.id,ok:true,result:{created:true}});
  assert.equal(relay.requests.get(newFile.id).content,undefined);
});

test("file CRUD rejects symlink aliases, overwrites and stale edits",async()=>{
  const root=await mkdtemp(join(tmpdir(),"oagent-crud-"));
  try{
    await mkdir(join(root,"src"));
    await mkdir(join(root,".git"));
    await writeFile(join(root,"src","old.ts"),"export const value = 1;\n");
    await writeFile(join(root,".git","config"),"private git metadata");
    await symlink(join(root,".git"),join(root,"linked"),"dir");
    const workspace={
      Uri:{file:fsPath=>({fsPath})},
      WorkspaceEdit:class{
        renameFile(from,to,options){this.from=from.fsPath;this.to=to.fsPath;this.options=options;}
      },
      workspace:{
        openTextDocument:async(uri)=>{
          const contents=await readFile(uri.fsPath,"utf8");
          return {uri, getText:()=>contents,isDirty:false};
        },
        applyEdit:async(edit)=>{await renameOnDisk(edit.from,edit.to);return true;},
        fs:{delete:async(uri,opts)=>{
          assert.equal(opts.recursive,false);
          assert.equal(opts.useTrash,true);
          await rm(uri.fsPath);
        }},
      },
      window:{showWarningMessage:async()=> "Move to Trash"},
    };
    await assert.rejects(()=>listWorkspaceFolder(root,"linked"),/Symbolic links/);
    await assert.rejects(()=>readWorkspaceText(root,"linked/config",workspace),/Symbolic links/);
    await assert.rejects(()=>createWorkspaceText(root,"linked/new.ts","bad",workspace),/Symbolic links/);
    const added=await createWorkspaceText(root,"src/new.ts","// hello",workspace);
    assert.equal(added.created,true);
    assert.equal(await readFile(join(root,"src","new.ts"),"utf8"),"// hello");
    await assert.rejects(()=>createWorkspaceText(root,"src/new.ts","overwrite",workspace),/EEXIST/);
    await assert.rejects(()=>renameWorkspaceFile(root,"src/old.ts",
      "src/new.ts",hash("export const value = 1;\n"),workspace),/already exists/);
    await assert.rejects(()=>renameWorkspaceFile(root,"src/old.ts",
      "src/change.ts","0".repeat(64),workspace),/changed/);
    const renamed=await renameWorkspaceFile(root,"src/old.ts",
      "src/change.ts",hash("export const value = 1;\n"),workspace);
    assert.equal(renamed.renamed,true);
    assert.equal((await stat(join(root,"src","change.ts"))).isFile(),true);
    await assert.rejects(()=>deleteWorkspaceFile(root,"src/change.ts",
      "0".repeat(64),workspace),/changed/);
    const deleted=await deleteWorkspaceFile(root,"src/change.ts",
      hash("export const value = 1;\n"),workspace);
    assert.equal(deleted.requestedTrash,true);
    await assert.rejects(()=>stat(join(root,"src","change.ts")) ,/ENOENT/);
  }finally{await rm(root,{recursive:true,force:true});}
});
