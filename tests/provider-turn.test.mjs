import test from "node:test";
import assert from "node:assert/strict";
import { runProviderTurn } from "../apps/gateway/src/provider-turn.mjs";
import { ControlPlane } from "../apps/control-plane/src/core.mjs";

const env = {
  OAGENT_ENABLE_CLAUDE_AGENT_SDK: "1", OAGENT_ENABLE_COPILOT_SDK: "1",
  OAGENT_WORKSPACE_ROOT: "/workspace", HOME: "/home/agent",
  OAGENT_API_TOKEN: "operator-secret-should-never-pass-to-sdk",
  OPENAI_API_KEY: "sensitive-provider-key",
};
const projectTask = (kind, mode = "read_only") => ({
  kind, parameters: { cwd: "/workspace/app", prompt: "Examine the build",
    mode, sessionId: null },
});
const realpathImpl = async v => v;
test("Claude Agent SDK streams real text, rejects writes in read-only and hides backend credentials", async () => {
  let captured, permissions = 0;
  const updates = [];
  const fakeQuery = options => {
    captured = options.options;
    return (async function* () {
      const decision = await options.options.canUseTool("Write",
        { file_path: "/workspace/app/main.js" });
      assert.equal(decision.behavior, "deny");
      yield { type: "system", subtype: "init",
        session_id: "claude-session-id-1234" };
      yield { type: "stream_event", event: {
        type: "content_block_delta", delta: { type: "text_delta",
          text: "Real Claude output" } } };
      yield { type: "assistant", message: { content: [
        { type: "thinking", thinking: "private reasoning" },
        { type: "tool_use", name: "Read", input: { apiKey: "don't expose" } },
      ] } };
      yield { type: "result", result: "Finished plan", total_cost_usd: 0.01 };
    })();
  };
  const result = await runProviderTurn(projectTask("claude_agent_turn"), {
    importSdk: async name => { assert.equal(name,"@anthropic-ai/claude-agent-sdk");return {query:fakeQuery}; },
    realpathImpl, env, askPermission: async () => { permissions++; return true; },
    sendUpdate: async item => updates.push(item),
  });
  assert.equal(permissions, 0);
  assert.equal(result.sessionId, "claude-session-id-1234");
  assert.equal(result.response, "Finished plan");
  assert.equal(result.costUsd, 0.01);
  assert.ok(updates.some(x => x.type === "agent_delta" && x.text === "Real Claude output"));
  assert.doesNotMatch(JSON.stringify(updates), /private reasoning|don't expose|operator-secret|sensitive-provider/);
  assert.equal(captured.env.OAGENT_API_TOKEN, undefined);
  assert.equal(captured.env.OPENAI_API_KEY, undefined);
  assert.equal(captured.permissionMode, "default");
  assert.ok(captured.disallowedTools.includes("Write"));
});
test("Claude write permissions are individual; outside workspace and unknown tools fail closed", async () => {
  const requests = [];
  const fakeQuery = options => (async function* () {
    const allow = await options.options.canUseTool("Edit",
      { file_path: "/workspace/app/README.md" });
    const deny = await options.options.canUseTool("Edit",
      { file_path: "/home/other/secret" });
    const unknown = await options.options.canUseTool("BrowserOpen", {url:"https://evil.test"});
    assert.equal(allow.behavior,"allow");
    assert.equal(deny.behavior,"deny");
    assert.equal(unknown.behavior,"deny");
    yield { type: "result", result: "Changes reviewed" };
  })();
  const result = await runProviderTurn(projectTask("claude_agent_turn","workspace_write"), {
    importSdk: async () => ({query:fakeQuery}), env, realpathImpl,
    sendUpdate: async () => {},
    askPermission: async request => { requests.push(request); return true; },
  });
  assert.equal(result.providerStatus,"completed");
  assert.equal(requests.length,1);
  assert.equal(requests[0].kind,"permissions");
  assert.match(requests[0].description,/README.md/);
  assert.ok(/^[a-zA-Z0-9_-]{8,120}$/.test(requests[0].id));
});
test("GitHub Copilot SDK session returns streamed answer, denies shell in read-only and disconnects", async () => {
  const events = {}, updates = [];
  let seenOptions, handlerDecisions, ended = 0, closed = 0, safeEnv;
  class FakeCopilot {
    constructor(options) { safeEnv = options.env; }
    async start() {}
    async createSession(options) {
      seenOptions = options;
      return {
        sessionId: "copilot-session-12345",
        on: (name, cb) => { events[name] = cb; },
        sendAndWait: async ({prompt}) => {
          assert.equal(prompt,"Examine the build");
          handlerDecisions = [
            await options.onPermissionRequest({ kind: "shell",
              fullCommandText: "del C:\\Projects\\app\\main.js" }),
            await options.onPermissionRequest({ kind: "read", path: "/workspace/app/README.md" }),
          ];
          events["assistant.message_delta"]?.({ data: { deltaContent: "Live Copilot" } });
          return { data: { content: "Final Copilot answer" } };
        },
        disconnect: async () => { ended++; },
      };
    }
    async stop() { closed++; }
  }
  const result = await runProviderTurn(projectTask("copilot_sdk_turn"), {
    importSdk: async name => { assert.equal(name,"@github/copilot-sdk");return {CopilotClient:FakeCopilot}; },
    realpathImpl, env, sendUpdate: async x => updates.push(x),
    askPermission: async () => { throw Error("Should not request permission"); },
  });
  assert.equal(seenOptions.streaming,true);
  assert.equal(handlerDecisions[0].kind,"reject");
  assert.equal(handlerDecisions[1].kind,"approve-once");
  assert.equal(result.response,"Final Copilot answer");
  assert.equal(result.sessionId,"copilot-session-12345");
  assert.equal(ended,1);
  assert.equal(closed,1);
  assert.equal(safeEnv.OAGENT_API_TOKEN,undefined);
  assert.ok(updates.some(u => u.text === "Live Copilot"));
});
test("Provider worker must advertise its explicit SDK capability before task can be scheduled", () => {
  const c = new ControlPlane();
  c.registerWorker({id:"worker-123456",name:"Enrolled machine",capabilities:[
    "system_info", "claude_agent_turn",
  ]});
  const request = kind => ({
    workerId:"worker-123456",kind,cwd:"/workspace/app",
    prompt:"Read the project",mode:"read_only",
  });
  assert.throws(() => c.createTask(request("copilot_sdk_turn"),"unique-key-copilot1234"),
    /not enrolled/);
  const ok = c.createTask(request("claude_agent_turn"),"unique-key-claude12345");
  assert.equal(ok.status,"waiting_for_approval");
  assert.equal(c.decide(ok.id,true).status,"queued");
  const work = c.claim("worker-123456");
  assert.equal(work.kind,"claude_agent_turn");
  c.appendTaskUpdate("worker-123456",work.id,{type:"agent_delta",text:"Real output"});
  const a = c.requestCodexApproval("worker-123456",work.id,{
    id:"approval-12345678",kind:"permissions",description:"Edit README.md" });
  assert.equal(a.state,"pending");
  assert.equal(c.decideCodexApproval(work.id,a.id,false).state,"denied");
  assert.equal(c.codexApprovalStatus("worker-123456",work.id,a.id).state,"denied");
});
