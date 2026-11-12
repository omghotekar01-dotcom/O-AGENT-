import test from "node:test";
import assert from "node:assert/strict";
import { ControlPlane } from "../apps/control-plane/src/core.mjs";
import { ProjectHub } from "../apps/control-plane/src/project-hub.mjs";
import { normalizeCodexTasks, readCodexCloudTasks } from "../apps/gateway/src/codex-cloud.mjs";

function stubAi() {
  let call = 0;
  return {
    async send({ message, threadId, agentId }) {
      call++;
      return { id: threadId || "thread-" + call, agentId, messages: [
        { role: "user", content: message }, { role: "assistant", content: "Actual provider mock: " + message },
      ] };
    },
    getThread(id) { return { id, messages: [] }; },
  };
}
function makeHub(env = {}, fetchImpl = undefined, clock = () => Date.now()) {
  const core = new ControlPlane({}, () => {});
  return { core, hub: new ProjectHub(core, stubAi(), { env, ...(fetchImpl ? { fetchImpl } : {}), now: clock }) };
}

test("owner projects persist, expose project chats and reject fabricated provider prompts", async () => {
  const { hub, core } = makeHub();
  const project = hub.create({ title: "Build my store", description: "Luxury skincare" });
  assert.equal(project.source, "oagent");
  assert.equal((await hub.list()).projects.length, 1);
  const reply = await hub.send(project.id, { agentId: "navigator", message: "Write a plan" });
  assert.equal(reply.thread.messages[1].content, "Actual provider mock: Write a plan");
  assert.ok(reply.project.threadId);
  assert.equal((await hub.details(project.id)).thread.id, reply.thread.id);
  const recovered = new ProjectHub(new ControlPlane(core.data), stubAi(), { env: {} });
  assert.equal((await recovered.list()).projects[0].title, "Build my store");
  await assert.rejects(hub.send("github:owner/repo", { message: "pretend to send" }), /Only O-AGENT-owned projects/);
});

test("GitHub projects and workflow statuses use real API responses, never fake counters", async () => {
  const seen = [];
  const fetchImpl = async (url, opts) => {
    seen.push({ url, headers: opts.headers });
    const data = url.includes("/actions/runs")
      ? { workflow_runs: [{ id: 3, name: "Android Build", status: "completed", conclusion: "failure", html_url: "https://github.com/test/repo/actions/runs/3" }] }
      : url.includes("/pulls?")
        ? [{ number: 19, title: "Fix issue", state: "open", html_url: "https://github.com/test/repo/pull/19" }]
        : { name: "repo", description: "Code project", html_url: "https://github.com/test/repo", pushed_at: "2026-11-12T08:00:00Z" };
    return { ok: true, json: async () => data };
  };
  const { hub } = makeHub({ OAGENT_GITHUB_REPOS: "test/repo" }, fetchImpl);
  const list = await hub.list();
  assert.equal(list.projects.length, 1);
  const project = list.projects[0];
  assert.equal(project.source, "github");
  assert.equal(project.state, "failed");
  assert.equal(project.runs[0].title, "Android Build");
  assert.equal(project.pullRequests[0].status, "open");
  assert.equal(project.control, "read_only");
  assert.equal(seen.length, 3);
  assert.ok(seen.every(x => x.url.startsWith("https://api.github.com/")));
  assert.equal((await hub.details(project.id)).project.title, "repo");
  assert.equal(seen.length, 3, "Cache avoids excess REST traffic");
});
test("GitHub authentication failures are explicit and do not expose tokens", async () => {
  const { hub } = makeHub({ OAGENT_GITHUB_REPOS: "test/private", OAGENT_GITHUB_TOKEN: "SENSITIVE_TOKEN" },
    async () => ({ ok: false, status: 403 }));
  const result = await hub.list();
  assert.equal(result.projects.length, 0);
  assert.equal(result.sourceErrors.length, 1);
  assert.match(result.sourceErrors[0].message, /denied/);
  assert.doesNotMatch(JSON.stringify(result), /SENSITIVE_TOKEN/);
});
test("GitHub repo config rejects arbitrary URLs and untrusted hosts", async () => {
  const { hub } = makeHub({ OAGENT_GITHUB_REPOS: "http://internal/path,good/repo" }, async url => ({
    ok: true, json: async () => url.includes("/actions/runs")
      ? { workflow_runs: [] } : url.includes("/pulls?")
        ? [] : { name: "Good", html_url: "https://attacker.example/fake" },
  }));
  const list = await hub.list();
  assert.equal(list.projects.length, 1);
  assert.equal(list.projects[0].url, null);
});
test("optional Codex sync only accepts real-worker snapshot and marks stale data honestly", async () => {
  let now = 100000;
  const { hub, core } = makeHub({ OAGENT_ENABLE_CODEX_CLOUD_SYNC: "1" }, null, () => now);
  core.registerWorker({ id: "laptop", name: "Win" });
  const first = hub.publishCodex("laptop", {
    tasks: [{ id: "task-1234", title: "Create a site", status: "in_progress", url: "https://chatgpt.com/codex/tasks/task-1234" }],
  });
  assert.equal(first.accepted, 1);
  const snapshot = await hub.list();
  assert.equal(snapshot.projects[0].source, "codex_cloud");
  assert.equal(snapshot.projects[0].state, "in_progress");
  assert.equal(snapshot.projects[0].liveBrowser, false);
  now += 121000;
  assert.equal((await hub.list()).projects[0].state, "stale");
  assert.throws(() => hub.publishCodex("ghost", { tasks: [] }), /Unknown worker/);
  assert.throws(() => hub.publishCodex("laptop", { tasks: [{ id: "invalid space", title: "No" }] }), /Invalid Codex task ID/);
});
test("Codex CLI JSON data is bounded and command has no user-supplied shell arguments", async () => {
  const records = normalizeCodexTasks({ tasks: [{ id: "codex-a", title: "Test", status: "running" }] });
  assert.equal(records.length, 1);
  const tasks = await readCodexCloudTasks(async (exe, args, options) => {
    assert.ok(["codex", "powershell.exe"].includes(exe));
    assert.ok(args.join(" ").includes("cloud list"));
    assert.ok(options.timeout <= 30000);
    return { stdout: JSON.stringify({ tasks: [{ id: "codex-a", title: "Test" }] }) };
  });
  assert.equal(tasks[0].id, "codex-a");
});
