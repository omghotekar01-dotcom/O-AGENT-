import {execFileSync} from "node:child_process";
import {randomBytes,generateKeyPairSync} from "node:crypto";
import {readFile,writeFile,chmod,mkdir} from "node:fs/promises";
import {dirname,join} from "node:path";
import {fileURLToPath} from "node:url";
const dir=dirname(fileURLToPath(import.meta.url));
const file=join(dir,".env.local");
const realmPath=join(dir,".private","oagent-realm.json");
const realmTemplate=join(dir,"oagent-realm.json");
export function renderOwnerRealm(template,{origin,password}){
  if(!/^https:\/\/[a-z0-9.-]+\.ts\.net$/i.test(origin)||
      typeof password!=="string"||!/^[a-f0-9]{48}$/.test(password))
    throw Error("Invalid private realm origin or generated password");
  const raw=JSON.stringify(template);
  const replaced=raw.replaceAll("$"+"{OAGENT_ORIGIN}",origin)
    .replaceAll("$"+"{OAGENT_OWNER_PASSWORD}",password);
  if(replaced===raw||replaced.includes("$"+"{OAGENT_"))
    throw Error("Unresolved Keycloak realm template values");
  const realm=JSON.parse(replaced);
  const user=realm.users?.find(u=>u.username==="pilot-owner");
  const client=realm.clients?.find(u=>u.clientId==="oagent-web");
  if(user?.credentials?.[0]?.value!==password||
      client?.redirectUris?.[0]!==origin+"/" ||
      (client?.directAccessGrantsEnabled!==false && process.env.CI!=="true"))
    throw Error("Invalid generated private realm");
  return realm;
}
async function ensurePrivateRealm(secretContents,origin){
  const password=secretContents.match(
    /^OAGENT_OWNER_PASSWORD=([a-f0-9]{48})$/m)?.[1];
  if(!password)throw Error("Local owner password is missing or invalid");
  await mkdir(join(dir,".private"),{recursive:true,mode:0o700});
  const text=JSON.stringify(renderOwnerRealm(
    JSON.parse(await readFile(realmTemplate,"utf8")),{origin,password}),null,2)+"\n";
  try{
    const existing=await readFile(realmPath,"utf8");
    if(existing!==text)
      throw Error("Existing private Keycloak realm differs from current secrets. Never overwrite a live identity realm automatically.");
    return;
  }catch(error){if(error.code!=="ENOENT")throw error;}
  await writeFile(realmPath,text,{flag:"wx",mode:0o600});
  if(process.platform!=="win32")await chmod(realmPath,0o600);
}
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
    await ensurePrivateRealm(existing,origin);
    notify("Existing private secrets preserved: "+file);
    return {created:false,origin};
  }catch(error){if(error.code!=="ENOENT")throw error;}
  const names=["OAGENT_PG_ADMIN_PASSWORD","OAGENT_RUNTIME_PASSWORD",
    "OAGENT_MIGRATION_PASSWORD","OAGENT_KEYCLOAK_DB_PASSWORD",
    "OAGENT_KEYCLOAK_ADMIN_PASSWORD","OAGENT_OWNER_PASSWORD"];
  const pair=generateKeyPairSync("ec",{namedCurve:"prime256v1"});
  const pub=pair.publicKey.export({format:"jwk"});
  const priv=pair.privateKey.export({format:"jwk"});
  const vapidPub=Buffer.concat([Buffer.from([4]),
    Buffer.from(pub.x,"base64url"),Buffer.from(pub.y,"base64url")])
    .toString("base64url");
  const data=["# Generated locally; never share or commit.","OAGENT_ORIGIN="+origin,
    ...names.map(n=>n+"="+randomBytes(24).toString("hex")),
    "OAGENT_VAPID_PUBLIC_KEY="+vapidPub,
    "OAGENT_VAPID_PRIVATE_KEY="+priv.d].join("\n")+"\n";
  await writeFile(file,data,{flag:"wx",mode:0o600});
  if(process.platform!=="win32")await chmod(file,0o600);
  await ensurePrivateRealm(data,origin);
  notify("Private pilot passwords generated at "+file+" (not displayed).");
  notify("docker compose --env-file .env.local -f compose.yaml up -d --build");
  notify("tailscale serve --bg 8791");
  notify("Open on a phone in your tailnet: "+origin);
  return {created:true,origin};
}
if(process.argv[1]&&fileURLToPath(import.meta.url)===process.argv[1])
  await setupPilot();
