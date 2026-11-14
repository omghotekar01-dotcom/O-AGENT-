import test from "node:test";
import assert from "node:assert/strict";
import {randomUUID} from "node:crypto";
import {createMcp} from "../src/mcp.mjs";

test("official MCP v2 Streamable HTTP exposes real scoped tools and never an approval bypass",
  {timeout:15000},async()=>{
  const pool={connect:async()=>{throw Error("Read-only protocol enumeration should not query tenant database");}};
  const handler=createMcp({pool,config:{issuer:"https://issuer.example/",publicOrigin:"https://app.example"}});
  async function request(method,params={},scope="oagent:read"){
    const raw={jsonrpc:"2.0",id:1,method,params};
    const result=await handler.fetch(new Request("https://app.example/mcp",{
      method:"POST",headers:{
        "content-type":"application/json","accept":"application/json, text/event-stream",
        "mcp-protocol-version":"2025-11-25",
      },body:JSON.stringify(raw),
    }),{authInfo:{token:"verified-test-identity",clientId:"user-A",scopes:[scope]}});
    return {status:result.status,body:await result.text()};
  }
  try{
    const init=await request("initialize",{
      protocolVersion:"2025-11-25",
      capabilities:{},clientInfo:{name:"oagent-test-client",version:"1.0"},
    });
    assert.equal(init.status,200,init.body);
    assert.match(init.body,/o-agent/);
    const tools=await request("tools/list");
    assert.equal(tools.status,200,tools.body);
    for(const name of ["oagent_list_runs","oagent_list_approvals",
      "oagent_get_run","oagent_request_run"]){
      assert.match(tools.body,new RegExp(name));
    }
    assert.doesNotMatch(tools.body,/oagent_approve|arbitrary_shell|steal_session/);
    const denied=await request("tools/call",{name:"oagent_request_run",
      arguments:{deviceId:randomUUID(),kind:"workspace_inventory",
        mode:"read_only",prompt:"Inspect",cwd:""}},"oagent:read");
    assert.equal(denied.status,200,denied.body);
    assert.match(denied.body,/Write scope required/);
    assert.match(denied.body,/"isError":true/);
  }finally{await handler.close();}
});
