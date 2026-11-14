import {mkdir,readFile,writeFile,rename,stat,lstat,rm,chmod} from "node:fs/promises";
import {join,dirname,resolve} from "node:path";
import {randomBytes} from "node:crypto";
import {homedir} from "node:os";
import {pathToFileURL} from "node:url";
import {generateDeviceKeys,parseEd25519PublicKey,hexSha256} from "../../saas/src/device-crypto.mjs";

export const defaultDeviceStore=()=>process.env.OAGENT_DEVICE_STORE||
  join(homedir(),".oagent-cloud","device.json");
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
function publicOrigin(value) {
  const url=new URL(value);
  if(url.protocol!=="https:"||url.pathname!=="/"||url.username||url.password)
    throw Error("Use your O-AGENT HTTPS cloud endpoint");
  return url.origin;
}
export async function readIdentity(path=defaultDeviceStore()) {
  try{
    const info=await lstat(path);
    if(!info.isFile()||info.isSymbolicLink()||
        (process.platform!=="win32"&&(info.mode&0o077)!==0))
      throw Error("Insecure local device identity permissions");
    const identity=JSON.parse(await readFile(path,"utf8"));
    if(typeof identity.privateKeyPem!=="string"||
       typeof identity.publicKeyPem!=="string")
      throw Error("Incomplete local key store");
    return identity;
  }catch(error){
    if(error.code==="ENOENT")return null;
    throw Error("Local device identity could not be read securely");
  }
}
async function writeIdentity(path,record) {
  await mkdir(dirname(path),{recursive:true,mode:0o700});
  // A random temporary file avoids a stale .new artifact blocking enrollment
  // after an interrupted previous write. No plaintext copy is made off-host.
  const temp=path+".new-"+randomBytes(10).toString("hex");
  try{
    await writeFile(temp,JSON.stringify(record),{mode:0o600,flag:"wx"});
    await rename(temp,path);
    if(process.platform!=="win32")await chmod(path,0o600);
  }finally{await rm(temp,{force:true});}
}
export async function enrollCloudWorker({
  origin,name="My O-AGENT worker",
  path=defaultDeviceStore(),fetchImpl=fetch,wait=sleep,
  now=()=>Date.now(),notify=console.log,
}){
  const endpoint=publicOrigin(origin);
  let identity=await readIdentity(path);
  if(identity?.deviceId) return {deviceId:identity.deviceId,alreadyEnrolled:true};
  if(!identity){
    identity={...generateDeviceKeys(),createdAt:now()};
  }
  if(!identity.pairingToken||identity.pairingExpiresAt<=now()){
    const response=await fetchImpl(endpoint+"/v1/devices/enrollments",{
      method:"POST",headers:{"content-type":"application/json"},
      body:JSON.stringify({name,publicKeyPem:identity.publicKeyPem}),
      signal:AbortSignal.timeout(15000),
    });
    const data=await response.json().catch(()=>({}));
    if(!response.ok||!data.pairingToken)
      throw Error("Could not create a secure pairing request. Check the cloud endpoint.");
    identity.pairingToken=data.pairingToken;
    identity.pairingExpiresAt=now()+Number(data.expiresInSeconds)*1000;
    await writeIdentity(path,identity);
  }
  const fingerprint=hexSha256(parseEd25519PublicKey(identity.publicKeyPem))
    .slice(0,24);
  notify("Open on your authenticated phone or web browser:");
  notify(endpoint+"/#pair="+encodeURIComponent(identity.pairingToken));
  notify("Confirm device fingerprint: "+fingerprint);
  notify("The worker has its own Ed25519 key. No eight-digit pairing code.");
  const max=identity.pairingExpiresAt;
  while(now()<max){
    await wait(3500);
    const response=await fetchImpl(endpoint+"/v1/devices/enrollments/status",{
      method:"POST",headers:{"content-type":"application/json"},
      body:JSON.stringify({pairingToken:identity.pairingToken}),
      signal:AbortSignal.timeout(15000),
    });
    if(response.status===404)break;
    if(!response.ok)continue;
    const status=await response.json().catch(()=>({}));
    if(status.approved&&status.deviceId){
      identity.deviceId=status.deviceId;
      delete identity.pairingToken;
      delete identity.pairingExpiresAt;
      await writeIdentity(path,identity);
      notify("Device enrolled successfully. Start the tenant worker.");
      return {deviceId:identity.deviceId,alreadyEnrolled:false};
    }
  }
  throw Error("Pairing expired. Run the enrollment command again for a fresh link.");
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
  await enrollCloudWorker({
    origin:process.env.OAGENT_SAAS_ORIGIN,
    name:process.env.OAGENT_DEVICE_NAME||"My trusted agent workspace",
  });
}
