import {createMcpHandler,McpServer} from "@modelcontextprotocol/server";
import * as z from "zod/v4";
import {withIdentity} from "./store.mjs";
import {listRuns,listApprovals,runDetail,createRun} from "./operations.mjs";
import {randomBytes} from "node:crypto";
import {notifyTenant} from "./push.mjs";

const content=result=>({content:[{type:"text",text:JSON.stringify(result)}]});
/** Official MCP v2 stateless handler; app verifies OIDC + Origin before entry.
 * The write tool only creates a pending human-approval request.
 * There is deliberately NO MCP approve, shell, file-write or provider cookie tool.
 */
export function createMcp({pool,config}){
  return createMcpHandler(({authInfo})=>{
    const server=new McpServer({name:"o-agent",version:"0.1.0"});
    const identity={issuer:config.issuer,subject:authInfo?.clientId,
      scopes:new Set(authInfo?.scopes||[])};
    const scoped=fn=>withIdentity(pool,identity,fn);
    server.registerTool("oagent_list_runs",{
      description:"Read real recent O-AGENT runs within your authenticated workspace",
      inputSchema:z.object({}),
    },async()=>content({runs:await scoped(c=>listRuns(c))}));
    server.registerTool("oagent_list_approvals",{
      description:"List pending real approvals; use the owner app to approve or deny",
      inputSchema:z.object({}),
    },async()=>content({approvals:await scoped(c=>listApprovals(c))}));
    server.registerTool("oagent_get_run",{
      description:"Get one authorized run's status",
      inputSchema:z.object({runId:z.string().uuid()}),
    },async({runId})=>content(await scoped(c=>runDetail(c,runId))));
    server.registerTool("oagent_request_run",{
      description:"Create a new supervised run that requires separate mobile approval; does not execute by itself",
      inputSchema:z.object({
        deviceId:z.string().uuid(),
        kind:z.enum(["workspace_inventory","claude_agent_turn",
          "copilot_sdk_turn","codex_cli_turn"]),
        mode:z.enum(["read_only","workspace_write"]),
        prompt:z.string().max(8000).default("Inspect enrolled workspace files"),
        cwd:z.string().max(600).default(""),
        sessionId:z.string().min(8).max(120).optional(),
      }),
    },async(args)=>{
      // Require a distinct write scope; read-only MCP tokens cannot enqueue.
      if(!identity.scopes.has("oagent-operate"))
        return {isError:true,content:[{type:"text",text:"Write scope required"}]};
      const nonce=randomBytes(24).toString("base64url");
      let tenantId;
      const created=await scoped((c,t)=>{
        tenantId=t;
        return createRun(c,t,identity.subject,args,"mcp_"+nonce);
      });
      if(!created.reused)void notifyTenant(pool,tenantId,config).catch(()=>{});
      return content(created);
    });
    return server;
  },{responseMode:"json"});
}
