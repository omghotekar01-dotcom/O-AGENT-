import {execFileSync} from "node:child_process";
import {dirname} from "node:path";
import {fileURLToPath} from "node:url";
import {setupPilot} from "./setup.mjs";
import {checkPilot,formatDoctor} from "./doctor.mjs";

const folder=dirname(fileURLToPath(import.meta.url));
const execute=(binary,args)=>execFileSync(binary,args,{
  cwd:folder,stdio:["ignore","pipe","pipe"],encoding:"utf8",timeout:180000,
});
const compose=["compose","--env-file",".env.local","-f","compose.yaml"];
const allowedProxy=new Set(["http://127.0.0.1:8791",
  "http://localhost:8791","127.0.0.1:8791"]);
/** Fail closed if Tailscale already hosts any unrelated Serve or Funnel app.
 * Installing O-AGENT must not replace the user's existing private services.
 */
export function verifyPrivateServeAvailability(json,port=443){
  const parsed=typeof json==="string"?JSON.parse(json):json;
  if(parsed==null)return {compatible:true,existing:false};
  if(typeof parsed!=="object"||Array.isArray(parsed))
    throw Error("Invalid existing Tailscale Serve status");
  if(![443,8443].includes(port))throw Error("Unsupported HTTPS port");
  // Guard only OUR port; preserve unrelated Serve and Funnel sites on 443.
  const onPort=key=>{
    const value=String(key);
    if(/^\d+$/.test(value))return Number(value)===port;
    const m=value.match(/:(\d+)$/);
    return Number(m?m[1]:443)===port;
  };
  if(Object.entries(parsed.AllowFunnel||{}).some(([key,enabled])=>onPort(key)&&Boolean(enabled)))
    throw Error("Requested port already has a Funnel");
  const sites=Object.entries(parsed.Web||{}).filter(([key])=>onPort(key));
  const handlers=sites.flatMap(([,site])=>Object.values(site?.Handlers||{}));
  const tcp=Object.entries(parsed.TCP||{}).filter(([key])=>onPort(key));
  if(!sites.length&&!tcp.length)return {compatible:true,existing:false};
  if(!handlers.length||handlers.some(h=>typeof h?.Proxy!=="string"||
       !allowedProxy.has(h.Proxy))||tcp.some(([,v])=>v?.HTTPS!==true))
    throw Error("Another Tailscale Serve app is configured on the requested port");
  return {compatible:true,existing:true};
}
/**
 * Single-command, repeatable private pilot boot. No Funnel, router exposure,
 * paid cloud provisioning, provider auth bypass, or mobile/APK builds.
 * It never prints process output, which can contain environment secrets.
 */
export async function startFreePilot({
  setup=setupPilot,run=execute,doctor=checkPilot,
  notify=console.log,
}={}){
  const {origin}=await setup({notify});
  const servePort=Number(new URL(origin).port||443);
  try{
    run("docker",["compose","version"]);
  }catch{
    throw Error("Docker Compose is not ready. Install/start Docker Desktop.");
  }
  try{
    run("docker",[...compose,"config","--quiet"]);
  }catch{
    throw Error("Private Compose configuration is invalid. Run node doctor.mjs.");
  }
  try{
    verifyPrivateServeAvailability(
      run("tailscale",["serve","status","--json"]),servePort);
  }catch{
    throw Error("Existing Tailscale Serve/Funnel configuration could conflict. Review tailscale serve status manually; no service has been changed.");
  }
  try{
    run("docker",[...compose,"up","-d","--build"]);
  }catch{
    throw Error("Private services could not start. Inspect docker compose logs; no public ports were requested.");
  }
  try{
    // Serve (not Funnel) exposes the loopback gateway ONLY to tailnet devices.
    run("tailscale",["serve","--bg","--https="+servePort,"127.0.0.1:8791"]);
  }catch{
    throw Error("Tailscale Serve could not enable private HTTPS. Run tailscale serve status and check HTTPS in tailnet settings.");
  }
  notify("Private pilot requested on "+origin);
  const results=await doctor();
  notify(formatDoctor(results));
  if(!results.ready)notify("The stack was started but prerequisites remain unverified. Run node doctor.mjs after investigating the listed items.");
  return {origin,ready:results.ready,checks:results.checks};
}
if(process.argv[1]&&fileURLToPath(import.meta.url)===process.argv[1]){
  await startFreePilot();
}
