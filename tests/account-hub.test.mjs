import test from "node:test";
import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { ControlPlane } from "../apps/control-plane/src/core.mjs";
import { AccountHub } from "../apps/control-plane/src/account-hub.mjs";

function makeHub() {
  let persisted = null;
  const core = new ControlPlane({}, data => { persisted = JSON.stringify(data); });
  const calls = [];
  const hub = new AccountHub(core, {
    env: { OAGENT_VAULT_KEY_BASE64: randomBytes(32).toString("base64") },
    fetchImpl: async (url, opts) => {
      calls.push({ url, headers: opts.headers, body: JSON.parse(opts.body) });
      return { ok: true, json: async () => ({ output_text: "Real mock response" }) };
    },
  });
  return { core, hub, calls, persisted: () => persisted };
}

test("Invitation is one-time, expires, and issued token is securely hashed", () => {
  const { hub, core } = makeHub();
  const invite = hub.createInvitation({ label: "Second tester" });
  assert.match(invite.invitationCode, /^join_/);
  assert.equal(JSON.stringify(core.data).includes(invite.invitationCode), false);
  const joined = hub.claimInvitation({ invitationCode: invite.invitationCode, displayName: "Beta tester" });
  assert.equal(hub.authenticate(joined.token).role, "member");
  assert.equal(JSON.stringify(core.data).includes(joined.token), false);
  assert.throws(() => hub.claimInvitation({ invitationCode: invite.invitationCode, displayName: "Another" }), /expired or already used/);
  assert.equal(hub.authenticate("bad"), null);
  assert.equal(hub.members().length, 1);
});

test("Each invited user has separate encrypted BYOK secrets and cannot read another's conversations", async () => {
  const { hub, core, calls, persisted } = makeHub();
  const join = label => hub.claimInvitation({
    invitationCode: hub.createInvitation({ label }).invitationCode, displayName: label,
  });
  const alice = join("Alice");
  const bob = join("Bob");
  const aliceId = alice.user.id, bobId = bob.user.id;
  const aliceKey = "sk-alice-test-not-real-123456789";
  const bobKey = "sk-bob-test-not-real-123456789";
  hub.saveConnection(aliceId, "openai", { apiKey: aliceKey, model: "gpt-5.6-luna" });
  hub.saveConnection(bobId, "openai", { apiKey: bobKey, model: "gpt-5.6-luna" });
  assert.equal(persisted().includes(aliceKey), false);
  assert.equal(persisted().includes(bobKey), false);
  assert.equal(hub.listConnections(bobId).providers[0].connected, true);
  assert.equal(JSON.stringify(hub.listConnections(aliceId)).includes(aliceKey), false);
  assert.equal(JSON.stringify(core.data.accounts.connections[aliceId]).includes(aliceKey), false);
  assert.equal(hub.decrypt(aliceId, "openai", core.data.accounts.connections[aliceId].openai.secret), aliceKey);
  assert.throws(() => hub.decrypt(bobId, "openai", core.data.accounts.connections[aliceId].openai.secret));
  const aliceThread = await hub.send(aliceId, { provider: "openai", message: "My private question" });
  assert.equal(aliceThread.messages[1].content, "Real mock response");
  assert.equal(calls[0].headers.authorization, "Bearer " + aliceKey);
  assert.equal(calls[0].body.tools, undefined, "No machine permissions in personal AI chat");
  assert.equal(hub.threads(bobId).length, 0);
  assert.throws(() => hub.thread(bobId, aliceThread.id), /unavailable/);
  const bobThread = await hub.send(bobId, { provider: "openai", message: "Your private question" });
  assert.equal(bobThread.messages[1].content, "Real mock response");
  assert.equal(calls[1].headers.authorization, "Bearer " + bobKey);
  assert.equal(hub.threads(aliceId).length, 1);
  assert.equal(hub.threads(bobId).length, 1);
  hub.revokeMember(aliceId);
  assert.equal(hub.authenticate(alice.token), null);
  assert.equal(hub.threads(aliceId).length, 0);
  assert.equal(hub.listConnections(aliceId).providers[0].connected, false);
  assert.equal(hub.authenticate(bob.token).id, bobId);
});

test("Vault fails closed without master key, and old master cannot decrypt after rotation", () => {
  const { hub, core } = makeHub();
  const user = hub.claimInvitation({ invitationCode: hub.createInvitation().invitationCode, displayName: "A" });
  hub.saveConnection(user.user.id, "gemini", { apiKey: "gemini-fake-123456789", model: "gemini-2.5-flash" });
  const noMaster = new AccountHub(core, { env: {} });
  assert.equal(noMaster.listConnections(user.user.id).vaultReady, false);
  assert.throws(() => noMaster.runtime(user.user.id, "gemini"), /vault/);
  const newMaster = new AccountHub(core, { env: { OAGENT_VAULT_KEY_BASE64: randomBytes(32).toString("base64") } });
  assert.throws(() => newMaster.runtime(user.user.id, "gemini"), /could not be decrypted/);
});

test("Provider keys can be replaced, revoked and different providers coexist", async () => {
  const { hub, core } = makeHub();
  const uid = "owner";
  hub.saveConnection(uid, "openai", { apiKey: "sk-initial-key-12345678", model: "gpt-5.6-luna" });
  hub.saveConnection(uid, "gemini", { apiKey: "google-key-12345678", model: "gemini-2.5-flash" });
  hub.saveConnection(uid, "openai", { model: "gpt-5.6-terra" });
  assert.equal(hub.listConnections(uid).providers.filter(p => p.connected).length, 2);
  assert.equal(hub.decrypt(uid, "openai", core.data.accounts.connections[uid].openai.secret), "sk-initial-key-12345678");
  hub.deleteConnection(uid, "openai");
  assert.equal(hub.listConnections(uid).providers.find(p => p.id === "openai").connected, false);
  assert.equal(hub.listConnections(uid).providers.find(p => p.id === "gemini").connected, true);
  await assert.rejects(hub.send(uid, { provider: "openai", message: "Hi" }), /Connect your own provider/);
});
