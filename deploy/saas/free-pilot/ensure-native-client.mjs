import {spawn} from "node:child_process";
import {readFile} from "node:fs/promises";
import {dirname,join} from "node:path";
import {fileURLToPath} from "node:url";
import {randomBytes} from "node:crypto";

const folder=dirname(fileURLToPath(import.meta.url));
const base=["compose","--env-file",".env.local","-f","compose.yaml",
  "exec","-T","identity"];
const cli="/opt/keycloak/bin/kcadm.sh";
export const MOBILE_CLIENT_ID="oagent-mobile";
export const MOBILE_CALLBACK="com.omiiii.oagent:/oauth2redirect";
export function nativeClientFromTemplate(realm){
  const web=realm.clients?.find(c=>c.clientId==="oagent-web");
  if(!web||web.publicClient!==true||
      !web.protocolMappers?.some(m=>m.config?.["included.custom.audience"]==="oagent-api"))
    throw Error("Cannot find the expected scoped O-AGENT OAuth template");
  return {
    clientId:MOBILE_CLIENT_ID,name:"O-AGENT native Android and iOS",
    enabled:true,protocol:"openid-connect",publicClient:true,
    standardFlowEnabled:true,implicitFlowEnabled:false,
    directAccessGrantsEnabled:false,serviceAccountsEnabled:false,
    redirectUris:[MOBILE_CALLBACK],webOrigins:[],
    attributes:{"pkce.code.challenge.method":"S256"},
    defaultClientScopes:[...web.defaultClientScopes],
    protocolMappers:structuredClone(web.protocolMappers),
  };
}
export function validateNativeClient(client){
  if(client?.clientId!==MOBILE_CLIENT_ID||client.publicClient!==true||
    client.standardFlowEnabled!==true||client.implicitFlowEnabled!==false||
    client.directAccessGrantsEnabled!==false||
    client.serviceAccountsEnabled!==false||
    client.attributes?.["pkce.code.challenge.method"]!=="S256"||
    !Array.isArray(client.redirectUris)||client.redirectUris.length!==1||
    client.redirectUris[0]!==MOBILE_CALLBACK||
    !Array.isArray(client.webOrigins)||client.webOrigins.length!==0)
    throw Error("Existing mobile OAuth client differs from secure native policy");
  return true;
}
async function cmd(args,input=""){
  return new Promise((resolve,reject)=>{
    const child=spawn("docker",[...base,...args],{
      cwd:folder,windowsHide:true,timeout:30000,
      stdio:["pipe","pipe","pipe"]});
    let output="",done=false;
    child.stdout.on("data",chunk=>{
      output+=chunk.toString();
      if(output.length>30000)child.kill();
    });
    child.stderr.resume();
    child.once("error",()=>{
      if(!done){done=true;reject(Error("Docker Keycloak CLI is unavailable"));}
    });
    child.once("close",code=>{
      if(done)return;done=true;
      if(code!==0||output.length>30000)
        reject(Error("Keycloak admin operation unavailable"));
      else resolve(output.trim());
    });
    child.stdin.on("error",()=>{});
    child.stdin.end(input);
  });
}
export async function ensureNativeClient({remote=cmd,
  read=readFile,sleep=ms=>new Promise(r=>setTimeout(r,ms))}={}){
  const template=JSON.parse(await read(join(folder,"oagent-realm.json"),"utf8"));
  const target=nativeClientFromTemplate(template);
  const nonce=randomBytes(8).toString("hex");
  const credentialPath="/tmp/oagent-native-auth-"+nonce+".conf";
  const inputPath="/tmp/oagent-native-client-"+nonce+".json";
  const login='umask 077; KC_CLI_PASSWORD="$KC_BOOTSTRAP_ADMIN_PASSWORD" exec '+
    cli+" config credentials --server http://127.0.0.1:8080/auth --realm master "+
    "--user admin --config "+credentialPath;
  try{
    let ready=false;
    for(let attempt=0;attempt<18;attempt++){
      try{await remote(["sh","-c",login]);ready=true;break;}
      catch{if(attempt!==17)await sleep(2000);}
    }
    if(!ready)throw Error("Keycloak admin login not ready. O-AGENT mobile OAuth client was not installed.");
    const list=JSON.parse(await remote([cli,"get","clients","-r","oagent",
      "-q","clientId="+MOBILE_CLIENT_ID,"--config",credentialPath]));
    if(!Array.isArray(list)||list.length>1)
      throw Error("Unsafe duplicate mobile OAuth client records");
    if(list.length){
      const current=JSON.parse(await remote([cli,"get","clients/"+list[0].id,
        "-r","oagent","--config",credentialPath]));
      validateNativeClient(current);
      return {created:false,clientId:MOBILE_CLIENT_ID};
    }
    await remote(["sh","-c","umask 077; cat > "+inputPath],JSON.stringify(target));
    await remote([cli,"create","clients","-r","oagent",
      "-f",inputPath,"--config",credentialPath]);
    const result=JSON.parse(await remote([cli,"get","clients","-r","oagent",
      "-q","clientId="+MOBILE_CLIENT_ID,"--config",credentialPath]));
    if(result.length!==1||!result[0]?.id)
      throw Error("Mobile OAuth client was not persisted");
    const created=JSON.parse(await remote([cli,"get","clients/"+result[0].id,
      "-r","oagent","--config",credentialPath]));
    validateNativeClient(created);
    return {created:true,clientId:MOBILE_CLIENT_ID};
  }finally{
    try{await remote(["sh","-c","rm -f "+credentialPath+" "+inputPath]);}
    catch{}
  }
}
if(process.argv[1]&&fileURLToPath(import.meta.url)===process.argv[1]){
  try{
    const result=await ensureNativeClient();
    console.log("[PASS] Native mobile PKCE sign-in "+(result.created?
      "registered":"verified")+" (client oagent-mobile).");
  }catch{
    console.error("[FIX] Native mobile login could not be registered. "+
      "Check Keycloak admin access and preserve the existing identity database.");
    process.exitCode=1;
  }
}
