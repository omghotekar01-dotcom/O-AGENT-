import {execFileSync,spawn} from "node:child_process";
import {existsSync} from "node:fs";
import {join,dirname,resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {startFreePilot} from "../deploy/saas/free-pilot/start.mjs";
import {ensureNativeClient} from "../deploy/saas/free-pilot/ensure-native-client.mjs";
import {showMobileLogin} from "./show-mobile-login.mjs";

const root=resolve(dirname(fileURLToPath(import.meta.url)),"..");
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const dockerReady=()=>{
  try{
    execFileSync("docker",["info","--format","{{.ServerVersion}}"],{
      stdio:["ignore","pipe","pipe"],timeout:9000,windowsHide:true});
    return true;
  }catch{return false;}
};

/** Only launch the locally installed Docker Desktop; never install packages
 * or modify global OS settings without owner participation.
 */
export async function prepareDocker({
  ready=dockerReady,platform=process.platform,
  exists=existsSync,start=spawn,wait=delay,print=console.log,
  env=process.env,
}={}){
  if(ready())return;
  if(platform!=="win32")throw Error(
    "Docker engine is not running. Start Docker Desktop and try again.");
  const candidates=[
    join(env.ProgramFiles||"C:\\Program Files","Docker","Docker","Docker Desktop.exe"),
    ...(env.LOCALAPPDATA?[join(env.LOCALAPPDATA,"Programs","Docker","Docker","Docker Desktop.exe")]:[]),
  ];
  const program=candidates.find(exists);
  if(!program)throw Error(
    "Docker Desktop is not installed or could not be found. Install Docker Desktop first.");
  print("[SETUP] Starting installed Docker Desktop...");
  const child=start(program,[],{
    detached:true,windowsHide:true,stdio:"ignore",cwd:dirname(program)});
  child.unref?.();
  for(let attempt=0;attempt<40;attempt++){
    if(ready())return;
    await wait(3000);
  }
  throw Error("Docker Desktop did not become ready. Open it and resolve its on-screen error, then try again.");
}

export async function startWindowsWorker({
  command=spawn,platform=process.platform,
}={}){
  if(platform!=="win32")throw Error("This one-click shortcut is for Windows only.");
  const script=join(root,"scripts","select-oagent-workspace.ps1");
  return new Promise((done,fail)=>{
    const child=command("powershell.exe",[
      "-NoProfile","-ExecutionPolicy","Bypass","-STA","-File",script,
    ],{cwd:root,stdio:"inherit",windowsHide:false});
    child.once("error",()=>fail(Error(
      "Windows PowerShell could not start the trusted worker. Check your Windows installation.")));
    child.once("exit",(code,signal)=>{
      if(code===0)done();
      else fail(Error(signal?
        "Trusted worker was interrupted. Keep the O-AGENT window open.":
        "Trusted worker could not start. Read the [FIX] message above."));
    });
  });
}

/** Everything runs in sequence inside ONE console and ONE double-click.
 * Failure of a required step stops later steps; no bogus READY banner.
 * Hardware login and explicit fingerprint approval remain human decisions.
 */
export async function launchOneClick({
  prepare=prepareDocker,start=startFreePilot,register=ensureNativeClient,
  mobile=showMobileLogin,worker=startWindowsWorker,print=console.log,
}={}){
  print("===============================================");
  print(" O-AGENT   |   ONE-CLICK PRIVATE MISSION CONTROL");
  print("===============================================");
  print("[1/4] Checking the local Docker engine.");
  await prepare({print});
  print("[2/4] Starting and checking your private O-AGENT server.");
  const outcome=await start({notify:print});
  if(!outcome?.ready)throw Error(
    "The private server is not ready. Read the [FIX] checks above. No worker was started.");
  print("[3/4] Registering or verifying secure Android login.");
  const client=await register();
  print("[PASS] Native phone login "+(client?.created?"registered.":"verified."));
  print("[4/4] Showing your phone address and connecting your trusted project.");
  await mobile({print});
  print("On your phone: use the address above, sign in, then inspect the laptop");
  print("fingerprint in Devices. First-time owner approval cannot be skipped.");
  print("If asked, select ONE trusted project folder on this PC.");
  print("This window remains open while your laptop worker is available.");
  await worker();
  print("[INFO] Worker is no longer running. Local Docker services are not deleted.");
}

if(process.argv[1]&&fileURLToPath(import.meta.url)===resolve(process.argv[1])){
  launchOneClick().catch(error=>{
    // All operational errors are deliberate user-facing remedies.
    // Never print Docker credentials, environment values or stack traces.
    console.error("[FIX] "+(error instanceof Error?error.message:"O-AGENT setup failed."));
    process.exitCode=1;
  });
}
