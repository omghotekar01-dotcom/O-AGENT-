import test from "node:test";
import assert from "node:assert/strict";
import { ScreenShare } from "../apps/control-plane/src/screen-share.mjs";

const frame = Buffer.concat([Buffer.from([0xff,0xd8]), Buffer.alloc(120,0x22), Buffer.from([0xff,0xd9])]);
test("screen capture is disabled until human-enabled owner session and only accepts JPEG frames", () => {
  let clock=10000;
  const share=new ScreenShare({now:()=>clock});
  assert.equal(share.status().capturing,false);
  assert.throws(()=>share.frame(),/No fresh/);
  const started=share.start();
  assert.equal(started.capturing,true);
  assert.ok(started.captureToken.length>=40);
  assert.equal(started.fresh,false);
  assert.throws(()=>share.start(),/already active/);
  assert.throws(()=>share.publish("wrong",frame),/Invalid capture-session/);
  assert.throws(()=>share.publish(started.captureToken,Buffer.alloc(120)),/bounded JPEG/);
  assert.throws(()=>share.publish(started.captureToken,Buffer.alloc(240001)),/bounded JPEG/);
  const accepted=share.publish(started.captureToken,frame);
  assert.equal(accepted.frameSequence,1);
  assert.deepEqual(share.frame().bytes,frame);
  assert.equal(share.frameSince(1),null, "unchanged frame must return 204 in HTTP API");
  assert.equal(share.frameSince(0).sequence,1);
  assert.equal(share.status().fresh,true);
  assert.throws(()=>share.publish(started.captureToken,frame),/Frame rate capped/);
  clock+=600;
  assert.equal(share.publish(started.captureToken,frame).frameSequence,2);
  clock+=4100;
  assert.equal(share.status().fresh,false);
  assert.throws(()=>share.frame(),/No fresh/);
  assert.equal(share.stop().capturing,false);
  assert.throws(()=>share.publish(started.captureToken,frame),/No active/);
});
test("capture lease expires on server without retaining stale screenshots",()=>{
  let now=25000;const share=new ScreenShare({now:()=>now});
  const start=share.start();share.publish(start.captureToken,frame);
  now+=31*60*1000;
  assert.equal(share.status().capturing,false);
  assert.throws(()=>share.frame(),/No fresh/);
  const newLease=share.start();assert.notEqual(newLease.captureToken,start.captureToken);
});

test("new frame arrives at responsive capture interval, stale frames never reused",()=>{
  let now=100000;
  const share=new ScreenShare({now:()=>now});
  const started=share.start();
  share.publish(started.captureToken,frame);
  now+=179;
  assert.throws(()=>share.publish(started.captureToken,frame),/capture rate/);
  now+=2;
  assert.equal(share.publish(started.captureToken,frame).frameSequence,2);
  assert.equal(share.frameSince(2),null);
  now+=4001;
  assert.throws(()=>share.frameSince(2),/No fresh/);
});
