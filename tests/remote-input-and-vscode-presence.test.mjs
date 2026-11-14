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
  assert.equal(broker.action({type:"move",dx:3,dy:-4}).accepted,true);
  assert.deepEqual(broker.next("my-laptop").action,{type:"move",dx:3,dy:-4,id:1});
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

test("rapid pointer deltas coalesce without skipping click or keyboard order",()=>{
  let now=800000;
  const input=new RemoteInput({now:()=>now,captureFresh:()=>true});
  const {pairingCode}=input.prepare("my-laptop");
  input.pair({code:pairingCode});
  assert.equal(input.action({type:"move",dx:25,dy:5}).accepted,true);
  assert.equal(input.action({type:"move",dx:15,dy:-2}).coalesced,true);
  assert.equal(input.status().queueDepth,1);
  now+=20;
  input.action({type:"click",button:"left"});
  now+=20;
  input.action({type:"shortcut",name:"save"});
  input.action({type:"move",dx:10,dy:11});
  input.action({type:"move",dx:9,dy:4});
  assert.equal(input.status().queueDepth,4);
  assert.deepEqual(input.next("my-laptop").action,{type:"move",dx:40,dy:3,id:1});
  const clicked=input.next("my-laptop",{id:1,ok:true});
  assert.deepEqual(clicked.action,{type:"click",button:"left",id:2});
  assert.equal(clicked.lastInputResult.ok,true);
  assert.equal(clicked.lastInputResult.type,"move");
  const rejected=input.next("my-laptop",{id:2,ok:false});
  assert.deepEqual(rejected.action,{type:"shortcut",name:"save",id:3});
  assert.equal(rejected.lastInputResult.ok,false);
  assert.equal(rejected.lastInputResult.type,"click");
  assert.equal(JSON.stringify(rejected).includes("secret"),false);
  assert.deepEqual(input.next("my-laptop",{id:3,ok:true}).action,
    {type:"move",dx:19,dy:15,id:4});
  assert.equal(input.next("my-laptop").action,null);
  assert.throws(()=>input.action({type:"shortcut",name:"powershell"}),/Unsupported/);
});


test("trusted Windows helper allows owner one-tap control only during fresh capture", () => {
  let now=1000000, fresh=false, display=true;
  const input=new RemoteInput({now:()=>now,
    captureFresh:()=>fresh,captureDisplay:()=>display});
  const armed=input.prepare("my-laptop",{trusted:true});
  assert.equal(armed.trustedMode,true);
  assert.equal("pairingCode" in armed,false);
  assert.equal(input.status().trustedReady,true);
  assert.equal(input.status().paired,false);
  assert.throws(()=>input.activateTrusted(),/Choose a screen/);
  assert.throws(()=>input.pair({code:"12345678"}),/No pending/);
  fresh=true;
  input.next("my-laptop");
  const active=input.activateTrusted();
  assert.equal(active.paired,true);
  assert.equal(active.requiresLocalPairing,false);
  now+=25;
  const click=input.action({type:"tap",x:4500,y:7000,button:"left"});
  assert.equal(click.accepted,true);
  assert.deepEqual(input.next("my-laptop").action,
    {type:"tap",x:4500,y:7000,button:"left",id:1});
  input.stop();
  assert.equal(input.status().paired,false);
  assert.equal(input.status().trustedReady,true);
  assert.equal(input.next("my-laptop").action,null);
  input.activateTrusted();
  display=false;
  assert.throws(()=>input.action({type:"tap",x:100,y:100,button:"left"}),
    /full-display/);
  assert.throws(()=>input.action({type:"tap",x:10001,y:500,button:"left"}),
    /invalid/);
  assert.equal(input.action({type:"click",button:"left"}).accepted,true);
  fresh=false;
  input.next("my-laptop");
  assert.equal(input.status().paired,false,
    "Screen loss must revoke existing control, never silently auto-resume");
  fresh=true;
  input.activateTrusted();
  now+=20*60*1000+1;
  // An absent heartbeat immediately revokes the helper after the time jump.
  assert.throws(()=>input.next("my-laptop"),/not enabled/);
  assert.equal(input.status().trustedReady,false,
    "A disconnected helper must not stay armed after heartbeat timeout");
  const again=input.prepare("my-laptop",{trusted:true});
  assert.equal(again.ready,true);
  input.stop("my-laptop");
  assert.equal(input.status().trustedReady,false,
    "Local helper stop must revoke trusted control");
});

test("a trustworthy live helper resets the expired control lease to view-only",()=>{
  let now=1000;
  const broker=new RemoteInput({now:()=>now,captureFresh:()=>true});
  broker.prepare("my-laptop",{trusted:true});
  broker.activateTrusted();
  // Repeated local helper polls keep it online but must not extend consent.
  for(let i=0;i<241;i++){
    now+=5000;
    const result=broker.next("my-laptop");
    if(i<239)assert.equal(result.paired,true);
  }
  assert.equal(broker.status().paired,false);
  assert.equal(broker.status().trustedReady,true);
  broker.activateTrusted();
  assert.equal(broker.status().paired,true);
});

test("image paste remains ephemeral, bounded and requires active owner control",()=>{
  let now=700000;
  const broker=new RemoteInput({now:()=>now,captureFresh:()=>true});
  const png=Buffer.concat([
    Buffer.from([137,80,78,71,13,10,26,10]),Buffer.alloc(100,0x33),
  ]);
  assert.throws(()=>broker.image(png,"image/png"),/Pair/);
  broker.prepare("my-laptop",{trusted:true});
  broker.activateTrusted();
  assert.throws(()=>broker.image(Buffer.alloc(100),"image/png"),/Invalid image/);
  assert.throws(()=>broker.image(png,"image/gif"),/JPEG\/PNG/);
  assert.throws(()=>broker.image(Buffer.alloc(1500001),"image/png"),/1.5 MB/);
  now+=25;
  const queued=broker.image(png,"image/png");
  assert.equal(queued.accepted,true);
  assert.equal(JSON.stringify(broker.status()).includes("base64"),false);
  const event=broker.next("my-laptop").action;
  assert.equal(event.type,"paste_image");
  assert.equal(event.mimeType,"image/png");
  assert.deepEqual(Buffer.from(event.base64,"base64"),png);
  broker.stop();
  assert.equal(broker.next("my-laptop").action,null);
  assert.equal(broker.status().queueDepth,0);
});
