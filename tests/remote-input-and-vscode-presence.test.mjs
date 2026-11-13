import test from "node:test";
import assert from "node:assert/strict";
import { RemoteInput } from "../apps/control-plane/src/remote-input.mjs";
import { VscodePresence } from "../apps/control-plane/src/vscode-presence.mjs";

test("remote input requires live screen, visible local pairing code and worker heartbeat", () => {
  let now = 100000;
  let capture = false;
  const broker = new RemoteInput({ now: () => now, captureFresh: () => capture });
  assert.throws(() => broker.prepare("my-laptop"), /screen share/);
  capture = true;
  const pair = broker.prepare("my-laptop");
  assert.match(pair.pairingCode, /^[0-9]{8}$/);
  assert.equal(broker.status().awaitingPairing, true);
  assert.equal(broker.status().paired, false);
  assert.equal("pairingCode" in broker.status(), false, "owner cannot list the local pairing code");
  assert.throws(() => broker.action({ type: "click", button: "left" }), /Pair/);
  assert.throws(() => broker.pair({ code: "0000000" }), /code/);
  broker.next("my-laptop");
  broker.pair({ code: pair.pairingCode });
  assert.equal(broker.status().paired, true);
  now += 40;
  assert.deepEqual(broker.action({type:"move",dx:3,dy:-4}),{accepted:true});
  assert.deepEqual(broker.next("my-laptop").action,{type:"move",dx:3,dy:-4});
  now += 40;
  broker.action({type:"click",button:"left"});
  capture = false;
  assert.throws(() => broker.action({type:"click",button:"left"}), /unavailable/);
  assert.equal(broker.next("my-laptop").action, null);
  broker.stop("my-laptop");
  assert.equal(broker.status().paired, false);
});

test("input broker rejects malformed inputs, unpaired callers, expired lease and worker mismatch", () => {
  let now = 400000;
  const broker = new RemoteInput({ now: () => now, captureFresh: () => true });
  const pair = broker.prepare("trusted-laptop");
  assert.throws(() => broker.next("other-laptop"), /not enabled/);
  broker.pair({code:pair.pairingCode});
  for (const bad of [
    {type:"move",dx:999,dy:0},
    {type:"key",key:"powershell"},
    {type:"text",text:""},
    {type:"text",text:"X".repeat(301)},
    {type:"click",button:"superuser"},
    {type:"scroll",steps:50},
    {type:"unknown"},
  ]) {
    now += 40;
    assert.throws(() => broker.action(bad), /Invalid|Unsupported|out of range|Text input/);
  }
  now += 7000;
  assert.equal(broker.status().paired,false,"helper heartbeat lapse revokes input");
  const another=broker.prepare("trusted-laptop");
  now += 120001;
  assert.throws(() => broker.pair({code:another.pairingCode}),/No pending/);
});

test("pairing locks out after repeated invalid codes", () => {
  let now = 500000;
  const broker = new RemoteInput({now:()=>now,captureFresh:()=>true});
  const {pairingCode} = broker.prepare("my-laptop");
  const invalid = pairingCode === "12345678" ? "87654321" : "12345678";
  for(let i=0;i<5;i++) assert.throws(()=>broker.pair({code:invalid}),/Incorrect/);
  assert.equal(broker.status().awaitingPairing,false);
  assert.throws(()=>broker.pair({code:pairingCode}),/No pending/);
});

test("editor source control snapshots are ephemeral and contain only bounded filenames", () => {
  let now = 160000;
  const feed = new VscodePresence({now:()=>now});
  const value = {workspace:"C:\\Projects\\MyApp",changed:[
    {path:"src/main.dart",status:"modified"},
    {path:"lib/new.dart",status:"untracked"},
    {path:"src/wip.dart",status:"unsaved"},
  ]};
  feed.publish("vscode-laptop",value);
  const result=feed.list();
  assert.equal(result.items.length,1);
  assert.equal(result.items[0].changed.length,3);
  assert.equal(result.items[0].workerId,"vscode-laptop");
  assert.equal(JSON.stringify(result).includes("sourceCode"),false);
  assert.throws(()=>feed.publish("vscode-laptop",
    {workspace:"C:\\tmp",changed:[{path:"foo",status:"unknown"}]}),/Invalid/);
  assert.throws(()=>feed.publish("vscode-laptop",
    {workspace:"C:\\tmp",changed:Array.from({length:101},()=>({path:"foo",status:"modified"}))}),/Invalid/);
  now+=21000;
  assert.deepEqual(feed.list().items,[]);
});
