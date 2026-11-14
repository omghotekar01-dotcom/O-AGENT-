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
