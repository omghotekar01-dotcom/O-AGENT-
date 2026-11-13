import test from "node:test";
import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { ControlPlane } from "../apps/control-plane/src/core.mjs";
import { AccountHub } from "../apps/control-plane/src/account-hub.mjs";

test("Real GitHub identity and readonly repositories are verified per account; no PAT leaked", async () => {
  const core = new ControlPlane();
  const requests = [];
  const hub = new AccountHub(core, { env: { OAGENT_VAULT_KEY_BASE64: randomBytes(32).toString("base64") },
    fetchImpl: async (url, options) => {
      requests.push({url, options});
      if (url.endsWith("/user")) return { ok: true, json: async () => ({ login: "real-user" }) };
      if (url.includes("/user/repos")) return { ok: true, json: async () =>
        [{ full_name: "real-user/example", description: "Example", private: true, default_branch: "main" }] };
      if (url.includes("/readme")) return { ok: true, json: async () =>
        ({ content: Buffer.from("# README from GitHub").toString("base64"), encoding: "base64", size: 20 }) };
      if (url.includes("api.openai.com")) return { ok: true, json: async () => ({ output_text: "AI reviewed README" }) };
      throw Error("unexpected remote call");
    }
  });
  const token = "github_pat_fake-example-test-1234567890";
  const conn = await hub.connectGithub("alice", { token });
  assert.equal(conn.connected, true);
  assert.equal(conn.login, "real-user");
  assert.equal(hub.githubStatus("bob").connected, false);
  assert.equal(JSON.stringify(core.data).includes(token), false);
  assert.deepEqual((await hub.githubRepos("alice"))[0].fullName, "real-user/example");
  await assert.rejects(hub.githubRepos("bob"), /Connect your personal GitHub/);
  hub.saveConnection("alice", "openai", { apiKey: "sk-fake-test-example-123456789", model: "gpt-test" });
  const response = await hub.send("alice", { provider: "openai", message: "Review the README",
    githubRepository: "real-user/example" });
  assert.equal(response.messages[1].content, "AI reviewed README");
  assert.equal(JSON.stringify(core.data.accounts.threads.alice).includes("README from GitHub"), false);
  const openaiRequest = JSON.parse(requests.find(x => x.url.includes("api.openai.com")).options.body);
  assert.match(JSON.stringify(openaiRequest.input), /README from GitHub/);
  hub.disconnectGithub("alice");
  assert.equal(hub.githubStatus("alice").connected, false);
});
