import test from "node:test";
import assert from "node:assert/strict";
import { ControlPlane, DomainError } from "../apps/control-plane/src/core.mjs";
import { AgentRuntime } from "../apps/control-plane/src/agent-runtime.mjs";

function makeCore() { return new ControlPlane({}, () => {}); }
const env = { OAGENT_AI_PROVIDER: "openai", OAGENT_AI_MODEL: "gpt-5.6-terra", OPENAI_API_KEY: "sk-test-local-mock-not-real" };
function fakeResponse(payload) { return { ok: true, json: async () => payload }; }

test("AI agents return correct configured status, not pretend active with missing key", async () => {
  const rt = new AgentRuntime(makeCore(), { env: {} });
  assert.equal(rt.status().configured, false);
  assert.equal(rt.status().agents.length, 3);
  await assert.rejects(rt.send({ agentId: "navigator", message: "hello" }), e => e instanceof DomainError && e.status === 503);
});

test("OpenAI Responses API executes a real backend tool and persists conversation", async () => {
  const core = makeCore();
  core.registerWorker({ id: "my-laptop", name: "OM-V16" });
  const calls = [];
  const fetchImpl = async (url, options) => {
    calls.push({ url, headers: options.headers, body: JSON.parse(options.body) });
    return fakeResponse(calls.length === 1
      ? { output: [{ type: "function_call", call_id: "call-a", name: "list_machines", arguments: "{}" }] }
      : { output: [{ type: "message", content: [{ type: "output_text", text: "OM-V16 is online." }] }] });
  };
  const rt = new AgentRuntime(core, { env, fetchImpl });
  const thread = await rt.send({ agentId: "navigator", message: "Which laptop is available?" });
  assert.equal(thread.messages.length, 2);
  assert.match(thread.messages[1].content, /OM-V16/);
  assert.equal(calls.length, 2);
  assert.equal(calls[0].url, "https://api.openai.com/v1/responses");
  assert.equal(calls[0].body.store, false);
  assert.equal(calls[1].body.input.at(-1).type, "function_call_output");
  assert.match(calls[1].body.input.at(-1).output, /my-laptop/);
  assert.equal(rt.threads()[0].id, thread.id);
  assert.equal(rt.getThread(thread.id).messages[0].role, "user");
  const resumed = new AgentRuntime(new ControlPlane({ agentThreads: core.data.agentThreads }), { env, fetchImpl });
  assert.equal(resumed.threads().length, 1);
});

test("AI requests for workspace inventory create a true human-approval gate", () => {
  const core = makeCore();
  core.registerWorker({ id: "laptop", name: "Laptop" });
  const rt = new AgentRuntime(core, { env });
  const result = JSON.parse(rt.safeTool("request_workspace_inventory", { worker_id: "laptop" }));
  assert.equal(result.ok, true);
  assert.equal(result.value.status, "waiting_for_approval");
  assert.equal(core.snapshot().tasks[0].status, "waiting_for_approval");
  assert.equal(core.claim("laptop"), null);
  const rejected = JSON.parse(rt.safeTool("request_system_health", { worker_id: "unknown" }));
  assert.equal(rejected.ok, false);
  assert.equal(core.snapshot().tasks.length, 1);
});

test("AI cannot trigger arbitrary shell operations", () => {
  const rt = new AgentRuntime(makeCore(), { env });
  const result = JSON.parse(rt.safeTool("run_shell_command", { command: "del *" }));
  assert.equal(result.ok, false);
  assert.match(result.error, /Unsupported AI tool/);
});

test("Anthropic Messages tool loop returns real results", async () => {
  const requests = [];
  const fetchImpl = async (url, opts) => {
    requests.push({ url, body: JSON.parse(opts.body) });
    return fakeResponse(requests.length === 1
      ? { stop_reason: "tool_use", content: [{ type: "tool_use", id: "tool-1", name: "list_recent_tasks", input: {} }] }
      : { stop_reason: "end_turn", content: [{ type: "text", text: "There are no recent tasks." }] });
  };
  const rt = new AgentRuntime(makeCore(), {
    env: { ANTHROPIC_API_KEY: "sk-ant-test-key-not-real", OAGENT_AI_PROVIDER: "anthropic", OAGENT_AI_MODEL: "claude-sonnet-4-5" },
    fetchImpl,
  });
  const result = await rt.send({ agentId: "researcher", message: "Check recent work" });
  assert.match(result.messages[1].content, /no recent tasks/);
  assert.equal(requests.length, 2);
  assert.equal(requests[0].url, "https://api.anthropic.com/v1/messages");
  assert.equal(requests[1].body.messages.at(-1).content[0].type, "tool_result");
});

test("Provider errors never leak credentials", async () => {
  const fetchImpl = async () => ({ ok: false, status: 401 });
  const rt = new AgentRuntime(makeCore(), { env, fetchImpl });
  await assert.rejects(rt.send({ agentId: "navigator", message: "Hello" }),
    e => e.status === 502 && !e.message.includes(env.OPENAI_API_KEY));
});

test("invalid inputs and mismatched agent/thread are rejected", async () => {
  const rt = new AgentRuntime(makeCore(), { env, fetchImpl: async () => fakeResponse({
    output: [{ type: "message", content: [{ type: "output_text", text: "Hi" }] }],
  }) });
  await assert.rejects(rt.send({ agentId: "missing", message: "Hi" }), e => e.status === 400);
  await assert.rejects(rt.send({ agentId: "navigator", message: "x".repeat(4001) }), e => e.status === 400);
  const thread = await rt.send({ agentId: "navigator", message: "Hi" });
  await assert.rejects(rt.send({ agentId: "operator", threadId: thread.id, message: "Hi" }), e => e.status === 409);
});

test("prompt improvement previews a real model rewrite without granting any tools", async () => {
  const calls = [];
  const fetchImpl = async (url, options) => {
    calls.push(JSON.parse(options.body));
    return { ok: true, json: async () => ({
      output: [{ type: "message", content: [{ type: "output_text", text: "Build a documented React landing page and run tests." }] }],
    }) };
  };
  const rt = new AgentRuntime(makeCore(), { env, fetchImpl });
  const result = await rt.refinePrompt({ target: "codex_cloud", message: "make website" });
  assert.match(result.proposed, /React landing page/);
  assert.equal(calls[0].tools, undefined, "Refiner must never invoke machine or provider tools");
  assert.equal(calls[0].store, false);
  assert.equal(rt.status().health, "connected");
  assert.ok(rt.status().lastVerifiedAt);
});
test("rate-limited model is not mislabeled connected even when a key exists", async () => {
  const rt = new AgentRuntime(makeCore(), {
    env,
    fetchImpl: async () => ({ ok: false, status: 429 }),
  });
  assert.equal(rt.status().configured, true);
  assert.equal(rt.status().health, "unverified");
  await assert.rejects(rt.refinePrompt({ message: "Improve this plan" }), err =>
    err.status === 503 && /429/.test(err.message));
  assert.equal(rt.status().health, "rate_limited");
  assert.match(rt.status().lastError, /billing\/credits/);
});
