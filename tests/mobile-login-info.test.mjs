import test from "node:test";
import assert from "node:assert/strict";
import {privateMobileOrigin,showMobileLogin} from "../scripts/show-mobile-login.mjs";

test("phone address displays only the configured private HTTPS origin",()=>{
  const settings="OAGENT_ORIGIN=https://my-pc.example-tailnet.ts.net:8443\n"+
    "OAGENT_OWNER_PASSWORD=SECRET-MUST-NOT-BE-DISPLAYED\n";
  assert.equal(privateMobileOrigin(settings),
    "https://my-pc.example-tailnet.ts.net:8443/");
  assert.equal(privateMobileOrigin("OAGENT_ORIGIN=https://laptop.sample.ts.net/\r\n"),
    "https://laptop.sample.ts.net/");
});

test("never accept another host, unexpected route or embedded credentials",()=>{
  for(const value of [
    "http://my-pc.sample.ts.net/","https://example.com/",
    "https://user:password@my-pc.sample.ts.net/",
    "https://my-pc.sample.ts.net/evil",
    "https://my-pc.sample.ts.net/?token=secret",
    "https://my-pc.sample.ts.net/#pair=secret",
    "https://my-pc.sample.ts.net:9999/",
    "https://my-pc.sample.ts.net.evil.com/",
  ])assert.throws(()=>privateMobileOrigin("OAGENT_ORIGIN="+value+"\n"));
  assert.throws(()=>privateMobileOrigin("NO_ORIGIN=true\n"));
  assert.throws(()=>privateMobileOrigin("OAGENT_ORIGIN=https://a.b.ts.net/\nOAGENT_ORIGIN=https://c.d.ts.net/\n"));
});

test("helper never prints sensitive values from local configuration",async()=>{
  const privateKey="VERY-PRIVATE-OWNER-PASSWORD";
  const lines=[];
  const address=await showMobileLogin({
    read:async()=>"OAGENT_ORIGIN=https://my-pc.sample.ts.net:8443\n"+
      "OAGENT_OWNER_PASSWORD="+privateKey+"\n",
    print:(line)=>lines.push(line),
  });
  assert.equal(address,"https://my-pc.sample.ts.net:8443/");
  assert.match(lines.join("\n"),/Private HTTPS address/);
  assert.doesNotMatch(lines.join("\n"),new RegExp(privateKey));
  assert.match(lines.join("\n"),/CONNECT-O-AGENT-WORKER\.cmd/);
});

test("missing initial setup produces a clear and non-secret instruction",async()=>{
  await assert.rejects(showMobileLogin({
    read:async()=>{const e=new Error("missing");e.code="ENOENT";throw e;},
    print:()=>{},
  }),/START-O-AGENT\.cmd/);
});
