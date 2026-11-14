import test from "node:test";
import assert from "node:assert/strict";
import {startFreePilot,verifyPrivateServeAvailability} from "../../../deploy/saas/free-pilot/start.mjs";
test("one command starts only private Docker Compose and Tailscale Serve",async()=>{
  const calls=[],messages=[];
  const setup=async()=>({created:true,origin:"https://laptop.tail.ts.net"});
  const run=(name,args)=>{calls.push([name,...args]);return args.includes("status")?"{}":"";};
  const doctor=async()=>({ready:true,checks:[]});
  const result=await startFreePilot({setup,run,doctor,notify:s=>messages.push(s)});
  assert.equal(result.ready,true);
  assert.deepEqual(calls.map(x=>x[0]),["docker","docker","tailscale","docker","tailscale"]);
  assert.ok(calls.some(x=>x.includes("--quiet")));
  assert.ok(calls.some(x=>x.includes("--build")));
  assert.ok(calls.some(x=>x.includes("127.0.0.1:8791")));
  assert.doesNotMatch(JSON.stringify(calls),/funnel|--public|--port=0\.0\.0\.0/);
  assert.ok(messages.some(x=>x.includes("Private pilot requested")));
});
test("pilot boot fails closed without running Compose when Docker is unavailable",async()=>{
  const commands=[];
  await assert.rejects(()=>startFreePilot({
    setup:async()=>({origin:"https://laptop.tail.ts.net"}),
    run:(name,args)=>{commands.push(name+" "+args.join(" "));throw Error("private docker error");},
    doctor:async()=>{throw Error("should never execute");},
    notify:()=>{},
  }),/Docker Compose is not ready/);
  assert.equal(commands.length,1);
});

test("Tailscale existing unrelated services cannot be silently overwritten",()=>{
  assert.deepEqual(verifyPrivateServeAvailability("{}"),
    {compatible:true,existing:false});
  const owned={TCP:{"443":{HTTPS:true}},
    Web:{"my.example.ts.net:443":{Handlers:{"/":{Proxy:"http://127.0.0.1:8791"}}}}};
  assert.deepEqual(verifyPrivateServeAvailability(owned),
    {compatible:true,existing:true});
  assert.throws(()=>verifyPrivateServeAvailability({
    Web:{"my.example.ts.net:443":{Handlers:{"/":{Proxy:"http://localhost:9999"}}}},
  }),/Another Tailscale/);
  assert.throws(()=>verifyPrivateServeAvailability({TCP:{"3399":{}}}),
    /may not be replaced/);
  assert.throws(()=>verifyPrivateServeAvailability({AllowFunnel:{"my.example.ts.net:443":true}}),
    /Funnel/);
  assert.throws(()=>verifyPrivateServeAvailability("not-json"),SyntaxError);
});
