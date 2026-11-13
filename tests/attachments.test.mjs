import test from "node:test";
import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { ControlPlane } from "../apps/control-plane/src/core.mjs";
import { AccountHub } from "../apps/control-plane/src/account-hub.mjs";

function make() {
  const calls = [];
  const core = new ControlPlane();
  const hub = new AccountHub(core, {
    env: { OAGENT_VAULT_KEY_BASE64: randomBytes(32).toString("base64") },
    fetchImpl: async (_url, opts) => {
      calls.push(JSON.parse(opts.body));
      return { ok: true, json: async () => ({ output_text: "Attachment interpreted" }) };
    },
  });
  return { hub, calls, core };
}
test("Private encrypted attachment is only accessible within owning account", async () => {
  const { hub, calls, core } = make();
  const userA = "user-a", userB = "user-b";
  hub.saveConnection(userA, "openai", { apiKey: "sk-not-real-test-0123456789", model: "gpt-test" });
  hub.saveConnection(userB, "openai", { apiKey: "sk-another-test-0123456789", model: "gpt-test" });
  const upload = hub.saveAttachment(userA, { name: "notes.txt", mimeType: "text/plain",
    base64: Buffer.from("private notes for user A").toString("base64") });
  assert.equal(JSON.stringify(core.data).includes("private notes for user A"), false);
  assert.equal(hub.attachments(userB).length, 0);
  assert.throws(() => hub.resolveAttachments(userB, [upload.id]), /unavailable/);
  await assert.rejects(hub.send(userB, { provider: "openai", message: "Read", attachmentIds: [upload.id] }), /unavailable/);
  const reply = await hub.send(userA, { provider: "openai", message: "Read this", attachmentIds: [upload.id] });
  assert.match(JSON.stringify(calls[0].input), /private notes for user A/);
  assert.equal(JSON.stringify(reply).includes("private notes for user A"), false);
  assert.equal(reply.messages[0].attachments[0].name, "notes.txt");
  hub.deleteAttachment(userA, upload.id);
  assert.throws(() => hub.resolveAttachments(userA, [upload.id]), /unavailable/);
});
test("Images and PDFs pass native OpenAI multimodal inputs without stored plaintext", async () => {
  const { hub, calls, core } = make();
  hub.saveConnection("a", "openai", { apiKey: "sk-not-real-test-0123456789", model: "gpt-test" });
  const tinyPng = Buffer.concat([Buffer.from("89504e470d0a1a0a", "hex"), Buffer.alloc(18)]).toString("base64");
  const picture = hub.saveAttachment("a", { name: "figure.png", mimeType: "image/png", base64: tinyPng });
  const pdf = hub.saveAttachment("a", { name: "paper.pdf", mimeType: "application/pdf", base64: Buffer.from("%PDF-1.7\nsample").toString("base64") });
  await hub.send("a", { provider: "openai", message: "Describe", attachmentIds: [picture.id, pdf.id] });
  const input = calls[0].input[0].content;
  assert.equal(input[1].type, "input_image");
  assert.equal(input[2].type, "input_file");
  assert.equal(JSON.stringify(core.data.accounts.threads.a).includes("%PDF-"), false);
  assert.throws(() => hub.saveAttachment("a", { name: "../evil", mimeType: "text/plain", base64: Buffer.from("bad").toString("base64") }), /Unsupported/);
  assert.throws(() => hub.saveAttachment("a", { name: "wrong.pdf", mimeType: "application/pdf", base64: Buffer.from("not pdf").toString("base64") }), /format/);
});
test("Provider-native Claude and Gemini attachment mapping stays tool-free", async () => {
  for (const provider of ["anthropic", "gemini"]) {
    const { hub, calls } = make();
    hub.saveConnection("a", provider, { apiKey: "example-fake-key-123456789", model: "model-valid" });
    const file = hub.saveAttachment("a", { name: "brief.txt", mimeType: "text/plain", base64: Buffer.from("reference").toString("base64") });
    // Return provider-specific valid mocked responses.
    const runtime = hub.runtime("a", provider).runtime;
    const originalFetch = runtime.fetchImpl;
    runtime.fetchImpl = async (url, opts) => {
      calls.push(JSON.parse(opts.body));
      return { ok: true, json: async () => provider === "anthropic" ?
        { content: [{ type: "text", text: "Claude result" }] } :
        { candidates: [{ content: { parts: [{ text: "Gemini result" }] } }] } };
    };
    const result = await runtime.send({ agentId: "navigator", message: "Summarize", attachments: hub.resolveAttachments("a", [file.id]) });
    assert.ok(result.messages.length);
    assert.equal(calls[0].tools, undefined);
    if (provider === "gemini") assert.match(calls[0].contents[0].parts[0].text, /reference/);
    else assert.match(calls[0].messages[0].content[0].text, /reference/);
  }
});
