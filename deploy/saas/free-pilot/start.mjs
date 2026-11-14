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
export function verifyPrivateServeAvailability(json){
  const parsed=typeof json==="string"?JSON.parse(json):json;
  if(parsed==null)return {compatible:true,existing:false};
  if(typeof parsed!=="object"||Array.isArray(parsed))
    throw Error("Invalid existing Tailscale Serve status");
  if(Object.values(parsed.AllowFunnel||{}).some(Boolean))
    throw Error("An existing Funnel must be reviewed and disabled manually");
  const web=Object.values(parsed.Web||{});
  const handlers=web.flatMap(site=>Object.values(site?.Handlers||{}));
  const tcp=Object.keys(parsed.TCP||{});
  if(handlers.length===0){
    if(web.length || tcp.length || Object.keys(parsed.Services||{}).length)
      throw Error("Existing Tailscale configuration may not be replaced automatically");
    return {compatible:true,existing:false};
  }
  if(handlers.some(h=>typeof h?.Proxy!=="string"||
      !allowedProxy.has(h.Proxy))||tcp.some(p=>p!=="443"))
    throw Error("Another Tailscale Serve app is configured");
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
      run("tailscale",["serve","status","--json"]));
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
    run("tailscale",["serve","--bg","127.0.0.1:8791"]);
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
