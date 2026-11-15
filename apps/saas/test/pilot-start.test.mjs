import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {startFreePilot,verifyPrivateServeAvailability} from "../../../deploy/saas/free-pilot/start.mjs";
import {migrationRemedies} from "../../../deploy/saas/free-pilot/migrate-port.mjs";
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
  assert.ok(calls.some(x=>x.includes("127.0.0.1:8787")));
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
    Web:{"my.example.ts.net:443":{Handlers:{"/":{Proxy:"http://127.0.0.1:8787"}}}}};
  assert.deepEqual(verifyPrivateServeAvailability(owned),
    {compatible:true,existing:true});
  assert.throws(()=>verifyPrivateServeAvailability({
    Web:{"my.example.ts.net:443":{Handlers:{"/":{Proxy:"http://localhost:9999"}}}},
  }),/Another Tailscale/);
  assert.deepEqual(verifyPrivateServeAvailability({TCP:{"3399":{}}}),
    {compatible:true,existing:false});
  assert.throws(()=>verifyPrivateServeAvailability({AllowFunnel:{"my.example.ts.net:443":true}}),
    /Funnel/);
  assert.throws(()=>verifyPrivateServeAvailability("not-json"),SyntaxError);
});

test("HTTPS 8443 keeps another application on 443 untouched",async()=>{
  const other={TCP:{"443":{HTTPS:true}},Web:{
    "host.example.ts.net:443":{Handlers:{"/":{Proxy:"http://127.0.0.1:9000"}}}}};
  assert.deepEqual(verifyPrivateServeAvailability(other,8443),{compatible:true,existing:false});
  const calls=[];
  await startFreePilot({setup:async()=>({origin:"https://host.example.ts.net:8443"}),
    run:(cmd,args)=>{calls.push([cmd,...args]);return args.includes("status")?JSON.stringify(other):"";},
    doctor:async()=>({ready:true,checks:[]}),notify:()=>{}});
  assert.ok(calls.some(x=>x.includes("--https=8443")));
  assert.throws(()=>verifyPrivateServeAvailability({AllowFunnel:{"host.example.ts.net:8443":true}},8443),/Funnel/);
  assert.throws(()=>verifyPrivateServeAvailability({Web:{
    "host.example.ts.net:8443":{Handlers:{"/":{Proxy:"http://localhost:9999"}}}}},8443),/Another Tailscale/);
});

test("port migration failure stages are safe and actionable",()=>{
  for(const stage of ["check Docker Desktop","check existing O-AGENT data",
    "check Tailscale port 8443","verify private login settings"]){
    assert.match(migrationRemedies[stage],/\S/);
    assert.doesNotMatch(migrationRemedies[stage],/OAGENT_OWNER_PASSWORD=|TOKEN=|-----BEGIN/);
  }
  assert.match(migrationRemedies["check existing O-AGENT data"],/do not delete/);
});

test("existing 8443 -> 8787 mapping is reused without mutating Tailscale",async()=>{
  const configured={TCP:{"443":{HTTPS:true},"8443":{HTTPS:true}},Web:{
    "host.example.ts.net:443":{Handlers:{"/":{Proxy:"http://127.0.0.1:8000"}}},
    "host.example.ts.net:8443":{Handlers:{"/":{Proxy:"http://127.0.0.1:8787"}}}}};
  const calls=[],messages=[];
  const result=await startFreePilot({
    setup:async()=>({origin:"https://host.example.ts.net:8443"}),
    run:(cmd,args)=>{calls.push([cmd,...args]);return args.includes("status")?JSON.stringify(configured):"";},
    doctor:async()=>({ready:true,checks:[]}),notify:m=>messages.push(m),
  });
  assert.equal(result.ready,true);
  assert.deepEqual(calls.map(x=>x[0]),["docker","docker","tailscale","docker"]);
  assert.ok(messages.some(m=>m.includes("route preserved")));
  assert.deepEqual(verifyPrivateServeAvailability(configured,8443),
    {compatible:true,existing:true});
});

test("Windows guarded repair keeps 8787 route and never resets volumes",()=>{
  const script=readFileSync(new URL("../../../REPAIR-O-AGENT.cmd",import.meta.url),"utf8");
  assert.match(script,/choice \/c YN/i,"explicit consent before role changes");
  assert.match(script,/node repair-db-auth\\.mjs --apply/);
  assert.match(script,/node migrate-existing-port\\.mjs 8443 --apply/);
  assert.match(script,/node start\\.mjs/);
  assert.match(script,/localhost:8787/);
  assert.doesNotMatch(script,/docker compose down -v|tailscale serve reset|tailscale funnel/i);
  assert.doesNotMatch(script,/om-v16\\.tailbb6a8f\\.ts\\.net/);
});
