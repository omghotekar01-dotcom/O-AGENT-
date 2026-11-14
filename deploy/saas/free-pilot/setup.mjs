import {execFileSync} from "node:child_process";
import {randomBytes} from "node:crypto";
import {readFile,writeFile,chmod} from "node:fs/promises";
import {dirname,join} from "node:path";
import {fileURLToPath} from "node:url";
const dir=dirname(fileURLToPath(import.meta.url));
const file=join(dir,".env.local");
export function tailnetOrigin(env=process.env,execute=execFileSync) {
  let name=env.OAGENT_TAILNET_HOST;
  if(!name){
    let status;
    try{
      status=JSON.parse(execute("tailscale",["status","--json"],{
        encoding:"utf8",timeout:8000,stdio:["ignore","pipe","pipe"],
      }));
    }catch{throw Error("Install Tailscale and sign in on this computer first");}
    if(status.BackendState!=="Running")throw Error("Tailscale must be connected");
    name=status.Self?.DNSName;
  }
  name=String(name||"").replace(/^https:\/\//,"").replace(/\.$/,"");
  if(!/^[a-z0-9][a-z0-9-]{0,62}\.[a-z0-9][a-z0-9.-]{0,190}\.ts\.net$/i.test(name))
    throw Error("Use this computer's MagicDNS name ending .ts.net");
  return "https://"+name.toLowerCase();
}
export async function setupPilot({env=process.env,notify=console.log,execute=execFileSync}={}){
  const origin=tailnetOrigin(env,execute);
  try{
    const existing=await readFile(file,"utf8");
    if(!existing.includes("OAGENT_ORIGIN="+origin+"\n"))
      throw Error("Pilot already configured for a different tailnet URL. Do not silently rotate keys or overwrite.");
    notify("Existing private secrets preserved: "+file);
    return {created:false,origin};
  }catch(error){if(error.code!=="ENOENT")throw error;}
  const names=["OAGENT_PG_ADMIN_PASSWORD","OAGENT_RUNTIME_PASSWORD",
    "OAGENT_MIGRATION_PASSWORD","OAGENT_KEYCLOAK_DB_PASSWORD",
    "OAGENT_KEYCLOAK_ADMIN_PASSWORD","OAGENT_OWNER_PASSWORD"];
  const data=["# Generated locally; never share or commit.","OAGENT_ORIGIN="+origin,
    ...names.map(n=>n+"="+randomBytes(24).toString("hex"))].join("\n")+"\n";
  await writeFile(file,data,{flag:"wx",mode:0o600});
  if(process.platform!=="win32")await chmod(file,0o600);
  notify("Private pilot passwords generated at "+file+" (not displayed).");
  notify("docker compose --env-file .env.local -f compose.yaml up -d --build");
  notify("tailscale serve --bg 8791");
  notify("Open on a phone in your tailnet: "+origin);
  return {created:true,origin};
}
if(process.argv[1]&&fileURLToPath(import.meta.url)===process.argv[1])
  await setupPilot();
