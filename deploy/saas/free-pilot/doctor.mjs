import {execFileSync} from "node:child_process";
import {readFile,stat} from "node:fs/promises";
import {dirname,join} from "node:path";
import {fileURLToPath} from "node:url";
import {tailnetOrigin} from "./setup.mjs";

const directory=dirname(fileURLToPath(import.meta.url));
const secrets=join(directory,".env.local");
const atLeast=(major,minor)=>major>22||(major===22&&minor>=12);
const configuredOrigin=raw=>{
  const match=raw.match(/^OAGENT_ORIGIN=(https:\/\/[^\r\n]+)$/m);
  if(!match)throw Error("No OAGENT_ORIGIN in local pilot settings");
  const url=new URL(match[1]);
  if(url.protocol!=="https:" || url.port || url.pathname!=="/"||
      !/\.ts\.net$/i.test(url.hostname))throw Error("Not a private HTTPS Tailnet origin");
  return url.origin;
};
async function response(fetchImpl,url,headers={}){
  const r=await fetchImpl(url,{
    headers,redirect:"error",cache:"no-store",signal:AbortSignal.timeout(4500),
  });
  if(!r.ok)throw Error("HTTP "+r.status);
  return r;
}
async function json(fetchImpl,url,headers={}){
  const r=await response(fetchImpl,url,headers);
  return r.json();
}
/** Read-only checks. Return code and short remedies, never raw passwords,
 * raw command output, tokens, provider URLs or unsanitized exception text.
 */
export async function checkPilot({
  execute=execFileSync,fetchImpl=fetch,read=readFile,statFile=stat,
  nodeVersion=process.versions.node,
}={}){
  const checks=[];
  async function check(name,action,remedy){
    try{
      await action();checks.push({name,ok:true,message:"Ready"});
    }catch{checks.push({name,ok:false,message:remedy});}
  }
  const version=nodeVersion.split(".").map(Number);
  await check("Node.js",()=>{if(!atLeast(version[0],version[1]))
    throw Error("Old Node");},
    "Install Node.js 22.12+ before running local helpers.");
  let origin;
  await check("Private configuration",async()=>{
    const content=await read(secrets,"utf8");
    origin=configuredOrigin(content);
    const permissions=await statFile(secrets);
    const privateRealm=await statFile(join(directory,".private","oagent-realm.json"));
    if(process.platform!=="win32"&&(privateRealm.mode&0o077)!==0)
      throw Error("Unsafe local realm permissions");
    if(process.platform!=="win32"&&(permissions.mode&0o077)!==0)
      throw Error("Unsafe permissions");
    for(const name of ["OAGENT_RUNTIME_PASSWORD",
      "OAGENT_MIGRATION_PASSWORD","OAGENT_KEYCLOAK_ADMIN_PASSWORD",
      "OAGENT_OWNER_PASSWORD","OAGENT_VAPID_PUBLIC_KEY"]){
      if(!new RegExp("^"+name+"=[A-Za-z0-9_-]{20,}$","m").test(content))
        throw Error("Missing required secret");
    }
  },"Run node setup.mjs. Keep .env.local private and unreadable to other users.");
  await check("Docker Compose",()=>{
    execute("docker",["compose","version"],{encoding:"utf8",timeout:7000,
      stdio:["ignore","pipe","pipe"]});
  },"Install/start Docker Desktop (or compatible Compose) and retry.");
  await check("Tailscale connection",()=>{
    const current=tailnetOrigin({},execute);
    if(origin && origin!==current)throw Error("Wrong tailnet");
  },"Sign into Tailscale on this computer; check MagicDNS host matches setup.");
  await check("Private local gateway",async()=>{
    const health=await json(fetchImpl,"http://127.0.0.1:8791/health/ready");
    if(health.status!=="ready"||health.database!=="connected")
      throw Error("Health not ready");
  },"Run docker compose --env-file .env.local -f compose.yaml up -d --build; inspect docker compose logs.");
  if(origin){
    await check("Phone HTTPS route",async()=>{
      const health=await json(fetchImpl,origin+"/health/ready");
      if(health.status!=="ready")throw Error("Not ready");
    },"Run tailscale serve --bg 8791; enable HTTPS/MagicDNS and connect phone to same tailnet.");
    await check("OIDC identity provider",async()=>{
      const oidc=await json(fetchImpl,origin+
        "/auth/realms/oagent/.well-known/openid-configuration");
      if(oidc.issuer!==origin+"/auth/realms/oagent"||
        typeof oidc.authorization_endpoint!=="string"||
        typeof oidc.jwks_uri!=="string")
        throw Error("Issuer mismatch");
    },"Identity provider is not reachable or its exact issuer differs. Inspect Keycloak and Caddy logs.");
    await check("Owner dashboard",async()=>{
      const web=await json(fetchImpl,origin+"/v1/public-config");
      if(!web.authEnabled||web.redirectUri!==origin+"/"||
        web.clientId!=="oagent-web")
        throw Error("Invalid browser OAuth");
    },"Check OIDC web client, exact HTTPS redirect URI and SaaS startup logs.");
  }else{
    for(const name of ["Phone HTTPS route","OIDC identity provider","Owner dashboard"])
      checks.push({name,ok:false,message:"Configure the private pilot origin first."});
  }
  return {origin:origin||null,ready:checks.every(c=>c.ok),checks};
}
export function formatDoctor(data){
  return "O-AGENT private pilot checks\n"+
    data.checks.map(c=>(c.ok?"[PASS] ":"[FIX] ")+c.name+" — "+c.message).join("\n")+
    "\n"+(data.ready?
      "Private pilot prerequisites responded successfully. Sign-in, provider sessions and phone approvals still require real acceptance tests.":
      "Correct the items above. Never post your .env.local, private keys or token logs.");
}
if(process.argv[1]&&fileURLToPath(import.meta.url)===process.argv[1]){
  const results=await checkPilot();
  console.log(formatDoctor(results));
  if(!results.ready)process.exitCode=1;
}
