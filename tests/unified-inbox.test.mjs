import test from "node:test";
import assert from "node:assert/strict";
import { ControlPlane } from "../apps/control-plane/src/core.mjs";
import { buildOwnerApprovalInbox } from "../apps/control-plane/src/unified-inbox.mjs";
import { ProjectHub } from "../apps/control-plane/src/project-hub.mjs";

function fixture() {
  let now = 5_000_000;
  const core = new ControlPlane({}, () => {}, () => now);
  core.registerWorker({id: "device-1234", name: "Test laptop", capabilities: [
    "workspace_inventory", "codex_cli_turn", "claude_agent_turn",
  ]});
  let key = 0;
  function task(kind, params = {}) {
    now += 1;
    return core.createTask({workerId: "device-1234", kind,
      ...(kind === "workspace_inventory" ? {} :
        {cwd: "/project", projectId: "project-1234",
          sessionId: "session-12345678", prompt: "Review changes",
          mode: "workspace_write"}), ...params},
    "unique-inbox-test-key-" + ++key);
  }
  return {core, task, now: () => now, tick: ms => {now += ms;}};
}
test("inbox contains real task approvals but no queued/completed tasks", () => {
  const f=fixture();
  const t=f.task("workspace_inventory");
  const c=f.task("claude_agent_turn");
  let inbox=buildOwnerApprovalInbox(f.core.snapshot(),f.now());
  assert.equal(inbox.total,2);
  assert.equal(inbox.items[0].taskId,c.id);
  assert.equal(inbox.items[1].description,"Inspect enrolled workspace filenames");
  assert.equal(inbox.items[0].description,"Review changes");
  assert.equal(inbox.items[0].actionable,true);
  f.core.decide(t.id,false);
  f.core.decide(c.id,true);
  assert.equal(buildOwnerApprovalInbox(f.core.snapshot(),f.now()).total,0);
});
test("tool approvals have exact IDs, expiry and no made-up website permissions", () => {
  const f=fixture();
  const t=f.task("claude_agent_turn");
  f.core.decide(t.id,true);
  f.core.claim("device-1234");
  const item=f.core.requestCodexApproval("device-1234",t.id,
    {id:"allowed-tool-1234",kind:"permissions",description:"Edit README.md"});
  let inbox=buildOwnerApprovalInbox(f.core.snapshot(),f.now());
  assert.equal(inbox.total,1);
  assert.equal(inbox.items[0].actionKind,"tool");
  assert.equal(inbox.items[0].approvalId,item.id);
  assert.equal(inbox.items[0].description,"Edit README.md");
  f.tick(180001);
  inbox=buildOwnerApprovalInbox(f.core.snapshot(),f.now());
  assert.equal(inbox.total,0);
  assert.equal(inbox.expired,1);
});
test("offline owners see non-actionable requests; result limits do not change counts", () => {
  const f=fixture();
  f.task("workspace_inventory");
  f.task("workspace_inventory");
  f.tick(31000);
  const inbox=buildOwnerApprovalInbox(f.core.snapshot(),f.now(),1);
  assert.equal(inbox.total,2);
  assert.equal(inbox.items.length,1);
  assert.equal(inbox.hasMore,true);
  assert.equal(inbox.items[0].workerOnline,false);
  assert.equal(inbox.items[0].actionable,false);
});
test("project overview uses the authoritative inbox count even for inventory tasks", () => {
  const f=fixture();
  f.task("workspace_inventory");
  const hub=new ProjectHub(f.core,{status:()=>({configured:false})},
    {env:{},now:f.now});
  const overview=hub.remoteOverview();
  assert.equal(overview.pendingApprovals,1);
  assert.equal(overview.approvalInboxSummary.total,1);
  assert.equal(overview.approvalInbox[0].actionKind,"task");
  assert.equal(overview.schemaVersion,1);
});
test("unrecognized tasks and expired unknown tool events are never actionable", () => {
  const inbox=buildOwnerApprovalInbox({workers:[{id:"x",status:"online"}],
    tasks:[
      {id:"a",workerId:"x",kind:"arbitrary_browser_approval",
        status:"waiting_for_approval",createdAt:1},
      {id:"b",workerId:"x",kind:"claude_agent_turn",
        status:"running",approvals:{"invalid":{
          id:"bad",state:"pending",expiresAt:99999}}},
    ]},5000);
  assert.equal(inbox.total,0);
});
