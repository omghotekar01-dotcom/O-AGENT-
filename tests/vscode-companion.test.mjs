import test from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { ControlPlane } from "../apps/control-plane/src/core.mjs";
const require=createRequire(import.meta.url);
const {safeRelativePath,withinWorkspace}=require("../apps/vscode/src/path-policy.cjs");

test("VS Code local file open refuses path traversal and absolute paths",()=>{
  for(const value of ["../private.txt","nested/../../secret.txt","/etc/passwd",
    "C:\\Users\\Owner\\secrets.txt","foo//bar.txt","foo\\..\\bar.txt",
    "a\u0000b","",Array(360).join("x")]) {
    assert.equal(safeRelativePath(value),false,String(value));
  }
  assert.equal(safeRelativePath("src/main.ts"),true);
  assert.equal(safeRelativePath("assets\\logo.png"),true);
  assert.equal(withinWorkspace("/workspace/project","/workspace/project/src/main.ts"),true);
  assert.equal(withinWorkspace("/workspace/project","/workspace/project/../outside.txt"),false);
  assert.equal(withinWorkspace("/workspace/project","/workspace/project-other/private.txt"),false);
});
test("VS Code remote file-open is owner approved and worker enrollment scoped",()=>{
  const core=new ControlPlane();
  core.registerWorker({id:"vscode-machine01",name:"VS Code machine",capabilities:[
    "workspace_inventory","vscode_open_file",
  ]});
  assert.throws(()=>core.createTask({workerId:"vscode-machine01",
    kind:"vscode_open_file",relativePath:"../private.env"},
    "vscode-request-path-invalid"),/relative/);
  assert.throws(()=>core.createTask({workerId:"vscode-machine01",
    kind:"claude_agent_turn",cwd:"/workspace/app",prompt:"Run",mode:"read_only"},
    "vscode-other-capability"),/not enrolled/);
  const task=core.createTask({workerId:"vscode-machine01",
    kind:"vscode_open_file",relativePath:"src/main.ts"},"vscode-owner-request-test-001");
  assert.equal(task.status,"waiting_for_approval");
  assert.equal(core.claim("vscode-machine01"),null);
  core.decide(task.id,true);
  const claimed=core.claim("vscode-machine01");
  assert.equal(claimed.parameters.relativePath,"src/main.ts");
  core.finish("vscode-machine01",task.id,{
    ok:true,result:{opened:false,reason:"Local VS Code user denied"},
  });
  assert.equal(core.getTask(task.id).result.opened,false);
});
