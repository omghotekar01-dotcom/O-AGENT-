import {createServer} from "node:http";
import {Readable} from "node:stream";
import {readFile} from "node:fs/promises";
import {pipeline} from "node:stream/promises";
import {createHmac,randomBytes} from "node:crypto";
import {resolve} from "node:path";
import {pathToFileURL} from "node:url";
import {readSaasConfig} from "./config.mjs";
import {createOidcVerifier} from "./oidc.mjs";
import {createPool,withIdentity,withTenant,assertTenantDatabaseSecurity,pruneEphemeralAuthenticationData} from "./store.mjs";
import {verifyDeviceHeaders} from "./device-crypto.mjs";
import {createMcp} from "./mcp.mjs";
import {registerPush,unregisterPush,pushStatus,notifyTenant} from "./push.mjs";
import {exportOwnerData} from "./export.mjs";
import {tenantUsage} from "./billing.mjs";
import {listWorkspaces,listTeamMembers,createTeamInvite,redeemTeamInvite,removeTeamMember,renameWorkspace} from "./team.mjs";
import {
  httpError,startEnrollment,inspectEnrollment,enrollmentStatus,approveEnrollment,listDevices,revokeDevice,
  updateCapabilities,heartbeat,createRun,listRuns,runDetail,
  listApprovals,decideApproval,claimRun,renewLease,finishRun,
  requestToolApproval,toolApprovalStatus,appendRunEvent,listRunEvents,
  cancelRun,resolveInterruptedRun,listAuditEvents,deleteOwnAccount,isUUID,
} from "./operations.mjs";

const reply=(res,status,value)=>{
  if(res.headersSent)return;
  res.writeHead(status,{"content-type":"application/json; charset=utf-8",
    "cache-control":"no-store","x-content-type-options":"nosniff",
    "referrer-policy":"no-referrer"});
  res.end(JSON.stringify(value));
};
async function bytes(req,max=16384) {
  const chunks=[];let len=0;
  for await (const chunk of req) {
    len+=chunk.length;
    if(len>max)throw httpError(413,"Request exceeds maximum size");
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}
function objectJson(data) {
  try{
    const value=data.length?JSON.parse(data.toString("utf8")):{};
    if(!value||typeof value!=="object"||Array.isArray(value))
      throw Error();
    return value;
  }catch{throw httpError(400,"Expected a JSON object");}
}
function expectedHost(config,req) {
  const host=req.headers.host;
  // Never trust X-Forwarded-* headers from arbitrary clients.
  if(typeof host!=="string" || host.toLowerCase()!==new URL(config.publicOrigin).host.toLowerCase())
    throw httpError(403,"Unexpected hostname");
  if(req.headers.origin && req.headers.origin!==config.publicOrigin)
    throw httpError(403,"Cross-origin request rejected");
}
function assertJson(req) {
  if(!/^application\/json(?:;|$)/i.test(String(req.headers["content-type"]||"")))
    throw httpError(415,"JSON content type required");
}
const capturePath=(path,pattern)=>path.match(pattern);

export function makeSaasServer({config,pool,authenticate,now=()=>Date.now()}){
  const verifier=authenticate||createOidcVerifier(config);
  const mcp=createMcp({pool,config});
  const ipSalt=randomBytes(32);
  const server=createServer(async(req,res)=>{
    try {
      const parsed=new URL(req.url||"/",config.publicOrigin);
      const path=parsed.pathname,method=req.method||"GET";
      if(method==="GET"&&path==="/health/live")
        return reply(res,200,{status:"alive"});
      if(method==="GET"&&path==="/health/ready") {
        await pool.query("SELECT 1");
        return reply(res,200,{status:"ready",database:"connected"});
      }
      expectedHost(config,req);
      const assets={"/":"../public/index.html",
        "/app.js":"../public/app.js","/style.css":"../public/style.css",
        "/manifest.webmanifest":"../public/manifest.webmanifest",
        "/sw.js":"../public/sw.js","/icon.svg":"../public/icon.svg"};
      if(method==="GET"&&Object.hasOwn(assets,path)){
        const content=await readFile(new URL(assets[path],import.meta.url));
        const tokenOrigin=config.webAuth?
          new URL(config.webAuth.tokenEndpoint).origin:"'self'";
        res.writeHead(200,{
          "content-type":path==="/"
            ?"text/html; charset=utf-8":path.endsWith(".js")
              ?"text/javascript; charset=utf-8":path.endsWith(".css")
                ?"text/css; charset=utf-8":path.endsWith(".svg")
                  ?"image/svg+xml":path.endsWith(".webmanifest")
                    ?"application/manifest+json":"application/octet-stream",
          "cache-control":"no-store",
          "content-security-policy":"default-src 'none'; script-src 'self'; "+
            "style-src 'self'; connect-src 'self' "+tokenOrigin+"; "+
            "img-src 'self' data:; base-uri 'none'; form-action 'none'; "+
            "frame-ancestors 'none'",
          "x-content-type-options":"nosniff","referrer-policy":"no-referrer",
          "service-worker-allowed":"/",
        });
        res.end(content);return;
      }
      if(method==="GET"&&path==="/v1/public-config")
        return reply(res,200,{
          authEnabled:!!config.webAuth,
          clientId:config.webAuth?.clientId??null,
          authorizationEndpoint:config.webAuth?.authorizationEndpoint??null,
          tokenEndpoint:config.webAuth?.tokenEndpoint??null,
          redirectUri:config.webAuth?.redirectUri??null,
          logoutEndpoint:config.webAuth?.logoutEndpoint??null,
          audience:config.audience,
          scope:"openid oagent-read oagent-operate",
        });
      if(method==="GET"&&path==="/.well-known/oauth-protected-resource")
        return reply(res,200,{
          resource:config.publicOrigin+"/mcp",
          authorization_servers:[config.issuer],
          scopes_supported:["oagent-read","oagent-operate"],
          bearer_methods_supported:["header"],
        });
      if(parsed.search&&!/^\/v1\/runs\/[0-9a-f-]{36}\/events$/i.test(path))
        throw httpError(400,"Unexpected query parameters");
      if(path==="/mcp"){
        if(!["GET","POST","DELETE"].includes(method))
          throw httpError(405,"Unsupported MCP method");
        let identity;
        try {identity=await verifier(req.headers.authorization,"oagent-read");}
        catch(error){
          if(error.status===401){
            res.writeHead(401,{"content-type":"application/json",
              "cache-control":"no-store",
              "www-authenticate":'Bearer resource_metadata="'+
                config.publicOrigin+'/.well-known/oauth-protected-resource"'});
            res.end(JSON.stringify({error:"MCP requires an authorized bearer token"}));
            return;
          }
          throw error;
        }
        // The official v2 handler is stateless. Identity is verified before
        // anything is forwarded; MCP never receives the raw bearer token.
        const body=method==="GET"?undefined:Readable.toWeb(req);
        // Internal MCP tools must never receive the original bearer token,
        // cookies, proxy headers or arbitrary untrusted request metadata.
        const protocolHeaders={
          accept:String(req.headers.accept||"application/json, text/event-stream"),
          ...(req.headers["content-type"]?
            {"content-type":String(req.headers["content-type"])}:{}),
          ...(req.headers["mcp-protocol-version"]?
            {"mcp-protocol-version":String(req.headers["mcp-protocol-version"])}:{}),
          ...(req.headers["mcp-session-id"]?
            {"mcp-session-id":String(req.headers["mcp-session-id"])}:{}),
        };
        const request=new Request(config.publicOrigin+path,{
          method,headers:protocolHeaders,body,
          ...(body?{duplex:"half"}:{}),
        });
        const answer=await mcp.fetch(request,{authInfo:{
          clientId:identity.subject,token:"validated-externally",
          scopes:[...identity.scopes],expiresAt:identity.expiresAt,
        }});
        res.writeHead(answer.status,Object.fromEntries(answer.headers));
        if(answer.body)await pipeline(Readable.fromWeb(answer.body),res);
        else res.end();
        return;
      }
      if(method==="POST"&&path==="/v1/devices/enrollments"){
        assertJson(req);
        const data=objectJson(await bytes(req,4096));
        const source=createHmac("sha256",ipSalt)
          .update(req.socket.remoteAddress||"unknown").digest();
        const value=await startEnrollment(pool,data,source);
        return reply(res,201,value);
      }
      if(method==="POST"&&path==="/v1/devices/enrollments/status"){
        assertJson(req);
        return reply(res,200,await enrollmentStatus(pool,
          objectJson(await bytes(req,1000)).pairingToken));
      }
      if(path.startsWith("/v1/device/")){
        // Workers cannot use a global shared bearer secret, a user token, or
        // an unverified device id as authority. Require per-request Ed25519
        // signature + short timestamp + database-backed replay nonce.
        if(!["POST","GET"].includes(method))throw httpError(405,"Invalid worker method");
        const raw=method==="POST"?await bytes(req,20000):Buffer.alloc(0);
        if(method==="POST")assertJson(req);
        const device=await verifyDeviceHeaders(pool,{
          headers:req.headers,method,path,rawBody:raw,now});
        const data=method==="POST"?objectJson(raw):{};
        const call=fn=>withTenant(pool,device.tenantId,async(client,tenantId)=>{
          const scoped=await client.query(
            "SELECT id FROM devices WHERE id=$1 AND revoked_at IS NULL",
            [device.deviceId]);
          if(!scoped.rowCount)throw httpError(403,"Device revoked or unavailable");
          return fn(client,tenantId);
        });
        if(method==="POST"&&path==="/v1/device/heartbeat")
          return reply(res,200,await call(c=>heartbeat(c,device.deviceId)));
        if(method==="POST"&&path==="/v1/device/capabilities")
          return reply(res,200,await call((c,t)=>updateCapabilities(
            c,t,device.deviceId,data.capabilities,data.workspaceRoot)));
        if(method==="POST"&&path==="/v1/device/claim")
          return reply(res,200,await call((c,t)=>claimRun(c,t,device.deviceId)));
        const runLease=capturePath(path,
          /^\/v1\/device\/runs\/([0-9a-f-]{36})\/(renew|complete|approvals|events)$/i);
        if(method==="POST"&&runLease){
          const id=runLease[1],op=runLease[2];
          if(op==="renew")return reply(res,200,
            await call(c=>renewLease(c,device.deviceId,id,data.leaseToken)));
          if(op==="complete")return reply(res,200,
            await call((c,t)=>finishRun(c,t,device.deviceId,id,data)));
          if(op==="approvals"){
            const item=await call((c,t)=>requestToolApproval(c,t,device.deviceId,id,data));
            reply(res,201,item);
            void notifyTenant(pool,device.tenantId,config).catch(()=>{});
            return;
          }
          if(op==="events")return reply(res,201,
            await call((c,t)=>appendRunEvent(c,t,device.deviceId,id,data)));
        }
        const approvalStatus=capturePath(path,
          /^\/v1\/device\/approvals\/([0-9a-f-]{36})$/i);
        if(method==="GET"&&approvalStatus)return reply(res,200,
          await call(c=>toolApprovalStatus(c,device.deviceId,approvalStatus[1])));
        throw httpError(404,"Unknown signed-device operation");
      }

      // Every account request requires a signed OIDC access token scoped to
      // this API audience. No caller-supplied tenant id or owner token.
      const write=method!=="GET";
      const identity=await verifier(req.headers.authorization,
        write?"oagent-operate":"oagent-read");
      // Explicit workspace selection is only honored after the verified
      // identity's team membership and minimum role are checked in SQL.
      const selectedWorkspace=req.headers["x-oagent-workspace"]||null;
      const requiredRole=path.startsWith("/v1/team/")||
        path.startsWith("/v1/billing/")||
        path.startsWith("/v1/account/")||
        path.startsWith("/v1/devices/enrollments/")||
        (path.startsWith("/v1/devices/") && path.endsWith("/revoke"))
          ?"owner":path==="/v1/audit"?"operator":
          write?"operator":"viewer";
      const asTenant=(fn,role=requiredRole)=>withIdentity(pool,identity,fn,{
        workspaceId:selectedWorkspace,requiredRole:role,
      });
      // Redemption uses a one-time hash-verified invite and signed OIDC
      // identity. It must not require pre-existing membership in that tenant.
      if(method==="POST"&&path==="/v1/team/join"){
        assertJson(req);
        const body=objectJson(await bytes(req,1000));
        return reply(res,200,await redeemTeamInvite(pool,identity,body.inviteToken));
      }
      if(method==="GET"&&path==="/v1/team/workspaces")
        return reply(res,200,{workspaces:await asTenant(c=>listWorkspaces(c,identity),"viewer")});
      if(method==="GET"&&path==="/v1/team/members")
        return reply(res,200,{members:await asTenant(listTeamMembers)});
      if(method==="POST"&&path==="/v1/team/invites"){
        assertJson(req);
        const body=objectJson(await bytes(req,1000));
        return reply(res,201,await asTenant((c,t)=>createTeamInvite(
          c,t,identity.subject,body.role)));
      }
      if(method==="POST"&&path==="/v1/team/members/remove"){
        assertJson(req);
        const body=objectJson(await bytes(req,1600));
        return reply(res,200,await asTenant((c,t)=>removeTeamMember(
          c,t,identity.subject,body)));
      }
      if(method==="POST"&&path==="/v1/team/settings"){
        assertJson(req);
        const body=objectJson(await bytes(req,500));
        return reply(res,200,await asTenant((c,t)=>renameWorkspace(
          c,t,identity.subject,body.name)));
      }
      if(method==="GET"&&path==="/v1/me")
        return reply(res,200,await asTenant(async(_c,tenant,role)=>({
          tenantId:tenant,subject:identity.subject,role,capabilities:[
            "device_enrollment","native_run_approval","scoped_mcp",
            "team_workspaces",
          ]}),"viewer"));
      if(method==="GET"&&path==="/v1/billing/usage")
        return reply(res,200,await asTenant(tenantUsage));
      if(method==="GET"&&path==="/v1/devices")
        return reply(res,200,{devices:await asTenant(c=>listDevices(c))});
      if(method==="GET"&&path==="/v1/audit")
        return reply(res,200,{events:await asTenant(c=>listAuditEvents(c))});
      if(method==="GET"&&path==="/v1/account/export")
        return reply(res,200,await asTenant(c=>exportOwnerData(c,identity)));
      if(method==="POST"&&path==="/v1/account/delete"){
        assertJson(req);
        const body=objectJson(await bytes(req,1200));
        return reply(res,200,await asTenant((c,t)=>
          deleteOwnAccount(c,t,identity.subject,body)));
      }
      if(method==="GET"&&path==="/v1/push/config")
        return reply(res,200,{enabled:!!config.push,
          vapidPublicKey:config.push?.publicKey??null});
      if(method==="GET"&&path==="/v1/push/status")
        return reply(res,200,await asTenant(c=>pushStatus(c)));
      if(method==="POST"&&path==="/v1/push/subscriptions"){
        if(!config.push)throw httpError(503,"Browser alerts are not configured");
        assertJson(req);const data=objectJson(await bytes(req,4000));
        return reply(res,201,await asTenant((c,t)=>registerPush(c,t,data)));
      }
      if(method==="DELETE"&&path==="/v1/push/subscriptions"){
        assertJson(req);const data=objectJson(await bytes(req,4000));
        return reply(res,200,await asTenant(c=>unregisterPush(c,data.endpoint)));
      }
      if(method==="POST"&&path==="/v1/devices/enrollments/inspect"){
        assertJson(req);const data=objectJson(await bytes(req,1000));
        return reply(res,200,await asTenant(c=>
          inspectEnrollment(c,data.pairingToken)));
      }
      if(method==="POST"&&path==="/v1/devices/enrollments/approve"){
        assertJson(req);const data=objectJson(await bytes(req,4096));
        return reply(res,201,await asTenant((c,t)=>approveEnrollment(
          c,t,identity.subject,data.pairingToken,data.expectedFingerprint)));
      }
      const revoke=capturePath(path,
        /^\/v1\/devices\/([0-9a-f-]{36})\/revoke$/i);
      if(method==="POST"&&revoke)return reply(res,200,
        await asTenant((c,t)=>revokeDevice(c,t,identity.subject,revoke[1])));
      if(method==="GET"&&path==="/v1/runs")
        return reply(res,200,{runs:await asTenant(c=>listRuns(c))});
      if(method==="POST"&&path==="/v1/runs"){
        assertJson(req);const data=objectJson(await bytes(req,10000));
        let notificationTenant;
        const created=await asTenant((c,t)=>{
          notificationTenant=t;
          return createRun(c,t,identity.subject,data,req.headers["idempotency-key"]);
        });
        reply(res,201,created);
        if(!created.reused)void notifyTenant(pool,notificationTenant,config).catch(()=>{});
        return;
      }
      const run=capturePath(path,/^\/v1\/runs\/([0-9a-f-]{36})$/i);
      if(method==="GET"&&run)return reply(res,200,
        await asTenant(c=>runDetail(c,run[1])));
      const ownedRunAction=capturePath(path,
        /^\/v1\/runs\/([0-9a-f-]{36})\/(cancel|resolve-interrupted)$/i);
      if(method==="POST"&&ownedRunAction){
        assertJson(req);
        const body=objectJson(await bytes(req,1200));
        const runId=ownedRunAction[1],operation=ownedRunAction[2];
        return reply(res,200,await asTenant((c,t)=>operation==="cancel"
          ?cancelRun(c,t,identity.subject,runId)
          :resolveInterruptedRun(c,t,identity.subject,runId,body)));
      }
      const eventRoute=capturePath(path,/^\/v1\/runs\/([0-9a-f-]{36})\/events$/i);
      if(method==="GET"&&eventRoute){
        const cursor=parsed.searchParams.get("after");
        if([...parsed.searchParams.keys()].some(k=>k!=="after")||
           (cursor!=null&&!/^\d{1,15}$/.test(cursor)))
          throw httpError(400,"Invalid event cursor");
        return reply(res,200,await asTenant(c=>listRunEvents(
          c,eventRoute[1],cursor==null?0:Number(cursor))));
      }
      if(method==="GET"&&path==="/v1/approvals")
        return reply(res,200,{approvals:await asTenant(c=>listApprovals(c))});
      const decision=capturePath(path,
        /^\/v1\/approvals\/([0-9a-f-]{36})\/decision$/i);
      if(method==="POST"&&decision){
        assertJson(req);const data=objectJson(await bytes(req,2000));
        return reply(res,200,await asTenant((c,t)=>decideApproval(
          c,t,identity.subject,decision[1],data)));
      }
      throw httpError(404,"Not found");
    }catch(error){
      // Do not leak DB SQL, provider errors, identity headers or stack traces.
      if(!res.headersSent && !res.destroyed)
        reply(res,Number.isSafeInteger(error.status)?error.status:500,
          {error:Number.isSafeInteger(error.status)?
            error.message:"Internal service error"});
      if(!error.status)console.error("SaaS request failed:",error.name);
    }
  });
  return {server,close:async()=>{await mcp.close();await new Promise(ok=>server.close(ok));}};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
  const config=readSaasConfig();
  const pool=createPool(config);
  await assertTenantDatabaseSecurity(pool);
  // Expired replay nonces otherwise grow with every signed heartbeat.
  // Failure is logged without interrupting existing agent runs.
  const clean=()=>void pruneEphemeralAuthenticationData(pool)
    .catch(()=>console.error("SaaS ephemeral authentication cleanup unavailable"));
  clean();
  const retention=setInterval(clean,60*60*1000);
  retention.unref();
  const app=makeSaasServer({config,pool});
  app.server.listen(config.port,config.host,()=>console.log(
    "O-AGENT isolated SaaS control plane ready on "+config.host+":"+config.port));
  const shutdown=async()=>{clearInterval(retention);await app.close();await pool.end();};
  process.once("SIGTERM",()=>void shutdown());
  process.once("SIGINT",()=>void shutdown());
}
