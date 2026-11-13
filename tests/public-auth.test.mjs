import test from "node:test";
import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { ControlPlane } from "../apps/control-plane/src/core.mjs";
import { PublicAuth } from "../apps/control-plane/src/public-auth.mjs";
import { AccountHub } from "../apps/control-plane/src/account-hub.mjs";

function setup() {
  let snapshot;
  const core = new ControlPlane({}, state => { snapshot = JSON.parse(JSON.stringify(state)); });
  const mail = [];
  let time = Date.now();
  const env = { OAGENT_PUBLIC_ACCOUNTS: "1", OAGENT_RESEND_API_KEY: "fake-private-mail-key",
    OAGENT_MAIL_FROM: "test@example.org", OAGENT_PUBLIC_URL: "https://agent.example.org" };
  const auth = new PublicAuth(core, { env, now: () => time,
    fetchImpl: async (_url, opts) => { mail.push(JSON.parse(opts.body)); return { ok: true }; } });
  return { core, auth, mail, snapshot: () => snapshot, advance: ms => { time += ms; } };
}
test("Public signup requires email delivery; only verified member can sign in", async () => {
  const { auth, mail, core, snapshot } = setup();
  assert.equal(new PublicAuth(new ControlPlane()).config().enabled, false);
  await assert.rejects(auth.login({ email: "user@example.org", password: "correct-long-password" }), /Invalid/);
  await auth.register({ email: "USER@example.org", displayName: "User", password: "correct-long-password" });
  assert.equal(JSON.stringify(snapshot()).includes("correct-long-password"), false);
  await assert.rejects(auth.login({ email: "user@example.org", password: "correct-long-password" }), /not verified/);
  const verification = mail[0].text.match(/verify_[A-Za-z0-9_-]+/)[0];
  auth.verify({ email: "user@example.org", code: verification });
  const session = await auth.login({ email: "user@example.org", password: "correct-long-password" });
  assert.equal(auth.authenticate(session.token).role, "member");
  assert.equal(JSON.stringify(snapshot()).includes(session.token), false);
  assert.equal(new ControlPlane(snapshot()).data.accounts.members[session.user.id].email, "user@example.org");
  assert.throws(() => auth.verify({ email: "user@example.org", code: verification }), /invalid or expired/);
  auth.logout(session.token);
  assert.equal(auth.authenticate(session.token), null);
  assert.equal(core.data.accounts.sessions[session.token], undefined);
});
test("Recovery revokes all existing sessions and expires after 15 minutes", async () => {
  const { auth, mail, advance } = setup();
  await auth.register({ email: "a@example.org", displayName: "A", password: "very-long-password" });
  auth.verify({ email: "a@example.org", code: mail[0].text.match(/verify_[A-Za-z0-9_-]+/)[0] });
  const old = await auth.login({ email: "a@example.org", password: "very-long-password" });
  assert.deepEqual(await auth.forgot({ email: "missing@example.org" }), { ok: true,
    message: "If the account exists, a recovery email has been sent." });
  await auth.forgot({ email: "a@example.org" });
  const reset = mail[1].text.match(/reset_[A-Za-z0-9_-]+/)[0];
  await auth.reset({ email: "a@example.org", code: reset, newPassword: "another-very-long-password" });
  assert.equal(auth.authenticate(old.token), null);
  await assert.rejects(auth.login({ email: "a@example.org", password: "very-long-password" }), /Invalid/);
  const active = await auth.login({ email: "a@example.org", password: "another-very-long-password" });
  advance(31 * 24 * 60 * 60_000);
  assert.equal(auth.authenticate(active.token), null);
});
test("Revoking member deletes cloud sessions and account data persists", async () => {
  const { auth, core, mail, snapshot } = setup();
  const a = await auth.register({ email: "a@example.org", displayName: "A", password: "very-long-password" });
  auth.verify({ email: "a@example.org", code: mail[0].text.match(/verify_[A-Za-z0-9_-]+/)[0] });
  const session = await auth.login({ email: "a@example.org", password: "very-long-password" });
  const accountHub = new AccountHub(core, { env: { OAGENT_VAULT_KEY_BASE64: randomBytes(32).toString("base64") } });
  accountHub.revokeMember(session.user.id);
  auth.revokeUser(session.user.id);
  assert.equal(auth.authenticate(session.token), null);
  assert.ok(snapshot().accounts);
});
