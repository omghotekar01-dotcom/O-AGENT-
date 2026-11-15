import test from "node:test";
import assert from "node:assert/strict";
import {withinRoot,validateCodexSessions} from "../src/codex-sessions.mjs";

test("portable signed-device session path check accepts verified Windows workspace",()=>{
  const root="C:\\Users\\ASUS\\OneDrive\\Desktop\\O Agent\\O-AGENT-";
  assert.equal(withinRoot(root,root),true);
  assert.equal(withinRoot(root,
    "C:\\Users\\ASUS\\OneDrive\\Desktop\\O Agent\\O-AGENT-\\src"),true);
  assert.equal(withinRoot(root,
    "c:\\users\\asus\\onedrive\\desktop\\o agent\\o-agent-\\src"),true);
  assert.equal(withinRoot(root,"C:\\Users\\ASUS\\Other"),false);
  assert.equal(withinRoot(root,"C:\\Users\\ASUS\\OneDrive\\Desktop\\O Agent\\O-AGENT-2"),false);
  assert.equal(withinRoot(root,root+"\\..\\other"),false);
  assert.equal(withinRoot(root,"D:\\Users\\ASUS\\O-AGENT-"),false);
  assert.equal(withinRoot(root,"/home/worker"),false);
  assert.equal(withinRoot(root,"\\\\server\\share\\folder"),false);
  assert.equal(withinRoot(root,"relative\\folder"),false);
});
test("portable Linux path validation rejects traversal and prefixes",()=>{
  assert.equal(withinRoot("/work/project","/work/project"),true);
  assert.equal(withinRoot("/work/project","/work/project/src"),true);
  assert.equal(withinRoot("/work/project","/work/project2"),false);
  assert.equal(withinRoot("/work/project","/work/project/../secret"),false);
  assert.equal(withinRoot("/work/project","C:\\Users\\ASUS\\O-AGENT-"),false);
});
test("saved Codex snapshot accepts verified Windows subfolder and rejects escape",()=>{
  const workspace="C:\\Users\\ASUS\\OneDrive\\Desktop\\O Agent\\O-AGENT-";
  const valid={
    sessionId:"saved-windows-thread-234",
    cwd:workspace+"\\apps\\flutter",title:"Existing Flutter thread",
    preview:"Review native UI",sourceKind:"vscode",
    updatedAt:"2026-11-15T04:00:00Z",
    messages:[{role:"user",text:"Continue O-AGENT app"}],
  };
  assert.equal(validateCodexSessions({sessions:[valid]},workspace).length,1);
  assert.throws(()=>validateCodexSessions({sessions:[{
    ...valid,cwd:"C:\\Users\\ASUS\\Other"
  }]},workspace),/Invalid verified Codex session/);
  assert.throws(()=>validateCodexSessions({sessions:[{
    ...valid,messages:[{role:"secret",text:"export password"}]
  }]},workspace),/Invalid stored session messages/);
});
