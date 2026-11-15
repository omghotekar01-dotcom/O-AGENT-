import {readFile} from "node:fs/promises";
import {dirname,join,resolve} from "node:path";
import {fileURLToPath} from "node:url";

const projectRoot=join(dirname(fileURLToPath(import.meta.url)),"..");
const configFile=join(projectRoot,"deploy","saas","free-pilot",".env.local");

/** Extracts only the private HTTPS origin; never displays login secrets. */
export function privateMobileOrigin(contents){
  const matches=[...contents.matchAll(/^OAGENT_ORIGIN=([^\r\n]*)\r?$/gm)];
  if(matches.length!==1)throw Error("Expected exactly one OAGENT_ORIGIN in local pilot settings.");
  let address;
  try{address=new URL(matches[0][1]);}
  catch{throw Error("Private HTTPS address in local pilot settings is invalid.");}
  const hostname=address.hostname.toLowerCase();
  const validHost=/^[a-z0-9][a-z0-9-]*(?:\.[a-z0-9][a-z0-9-]*)+\.ts\.net$/.test(hostname);
  if(address.protocol!=="https:"||!validHost||
     (address.port!==""&&address.port!=="8443")||
     address.username||address.password||address.search||address.hash||
     (address.pathname!==""&&address.pathname!=="/")){
    throw Error("Private address is not a valid Tailscale HTTPS root URL (443 or 8443).");
  }
  return address.origin+"/";
}

export async function showMobileLogin({read=readFile,print=console.log}={}){
  let contents;
  try{contents=await read(configFile,"utf8");}
  catch(error){
    if(error?.code==="ENOENT")throw Error("Private pilot not configured. Run START-O-AGENT.cmd first.");
    throw Error("Cannot read local private configuration. Check permissions and run START-O-AGENT.cmd.");
  }
  const address=privateMobileOrigin(contents);
  print("====================================================");
  print(" O-AGENT: CONNECT THE NATIVE ANDROID APP");
  print("====================================================");
  print("1. Keep Docker Desktop and the O-AGENT server running.");
  print("2. Sign into the SAME Tailscale account on PC and phone.");
  print("3. On phone, open O-AGENT > Private HTTPS address.");
  print("   Enter this exact address:");
  print("   "+address);
  print("4. Tap 'Sign in to native app'.");
  print("5. First login: username 'pilot-owner'. The initial password is");
  print("   OAGENT_OWNER_PASSWORD in deploy\\saas\\free-pilot\\.env.local.");
  print("   If you already changed your password, use the NEW password.");
  print("6. Keep START-O-AGENT.cmd open; the trusted worker starts here automatically.");
  print("7. On first pairing, approve the laptop fingerprint in app > Devices.");
  print("====================================================");
  print("This displays an address, NOT proof the server is online.");
  print("NEVER share passwords, .env.local, login tokens or pairing links.");
  return address;
}

if(process.argv[1]&&fileURLToPath(import.meta.url)===resolve(process.argv[1])){
  showMobileLogin().catch(error=>{
    console.error("[FIX] "+error.message);
    process.exitCode=1;
  });
}
