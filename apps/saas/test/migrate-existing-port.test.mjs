import test from "node:test";
import assert from "node:assert/strict";
import {mkdtemp,mkdir,readFile,writeFile,rm} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {migrateExisting,planClientOrigin} from "../../../deploy/saas/free-pilot/migrate-existing-port.mjs";
import {renderOwnerRealm} from "../../../deploy/saas/free-pilot/setup.mjs";

const from="https://host.example.ts.net",to=from+":8443";
const status={TCP:{"443":{HTTPS:true},"8443":{HTTPS:true}},Web:{
  "host.example.ts.net:443":{Handlers:{"/":{Proxy:"http://127.0.0.1:8000"}}},
  "host.example.ts.net:8443":{Handlers:{"/":{Proxy:"http://127.0.0.1:8787"}}}
}};
const clientId="00000000-1111-4222-8333-444444444444";
const client={id:clientId,clientId:"oagent-web",publicClient:true,
  redirectUris:[from+"/"],webOrigins:[from],
  attributes:{"pkce.code.challenge.method":"S256",
    "post.logout.redirect.uris":from+"/"}};
const execute=(bin,args)=>{
  assert.equal(bin,"tailscale");
  if(args[0]==="status")return JSON.stringify({
    BackendState:"Running",Self:{DNSName:"host.example.ts.net."}});
  if(args[0]==="serve")return JSON.stringify(status);
  throw Error("Unexpected CLI");
};
test("OIDC port migration preserves client PKCE and rejects customized redirect",()=>{
  const updated=planClientOrigin(client,from,to);
  assert.deepEqual(updated.redirectUris,[to+"/"]);
  assert.deepEqual(updated.webOrigins,[to]);
  assert.equal(updated.attributes["post.logout.redirect.uris"],to+"/");
  assert.equal(updated.attributes["pkce.code.challenge.method"],"S256");
  assert.equal(client.redirectUris[0],from+"/","never modify input");
  assert.throws(()=>planClientOrigin({...client,redirectUris:["https://evil.example/"]},
    from,to),/customized/);
});
test("existing port migration is read-only by default",async()=>{
  const result=await migrateExisting({read:async()=> "OAGENT_ORIGIN="+from+"\n",
    run:execute,remote:()=>{throw Error("should not access Keycloak")},
    backup:()=>{throw Error("should not write backups")}});
  assert.deepEqual(result,{status:"ready-to-migrate",target:to});
});
test("existing-DB migration requires backup and preserves original 443 mapping",async()=>{
  const directory=await mkdtemp(join(tmpdir(),"oagent-oidc-port-"));
  try{
    const privateFolder=join(directory,".private");
    await mkdir(privateFolder);
    const password="a".repeat(48);
    const settings="OAGENT_ORIGIN="+from+"\nOAGENT_OWNER_PASSWORD="+password+"\n";
    const template=JSON.parse(await readFile(new URL(
      "../../../deploy/saas/free-pilot/oagent-realm.json",import.meta.url),"utf8"));
    await writeFile(join(directory,"oagent-realm.json"),JSON.stringify(template));
    await writeFile(join(directory,".env.local"),settings);
    await writeFile(join(privateFolder,"oagent-realm.json"),
      JSON.stringify(renderOwnerRealm(template,{origin:from,password}),null,2)+"\n");
    let live={...client},pending=null,backup=false,verified=0;
    async function remote(args,input=""){
      if(args[0]==="sh"){
        if(input.startsWith("{"))pending=JSON.parse(input);
        return "";
      }
      if(args.includes("get")){
        if(args.includes("clients"))return JSON.stringify([{id:clientId}]);
        return JSON.stringify(live);
      }
      if(args.includes("update")){
        assert.equal(backup,true);
        assert.equal(verified,2);
        live=pending;
        return "";
      }
      throw Error("Unexpected Keycloak command");
    }
    const opts={directory,run:execute,remote,
      checkDb:async()=>({status:"already-matched"}),
      backup:async()=>{backup=true;},
      verify:async()=>{verified++;return true;},
      keyDirectory:join(directory,"separate-keys"),
      backupDirectory:join(directory,"backups")};
    const outcome=await migrateExisting({...opts,apply:true});
    assert.equal(outcome.status,"migrated");
    assert.equal(live.redirectUris[0],to+"/");
    assert.equal(live.webOrigins[0],to);
    assert.equal(live.attributes["pkce.code.challenge.method"],"S256");
    const saved=await readFile(join(directory,".env.local"),"utf8");
    assert.match(saved,/OAGENT_SERVE_PORT=8443/);
    assert.match(saved,/OAGENT_ORIGIN=https:\/\/host\.example\.ts\.net:8443/);
    assert.match(saved,/OAGENT_OWNER_PASSWORD=a{48}/);
    assert.equal((await migrateExisting(opts)).status,"already-migrated");
  }finally{await rm(directory,{recursive:true,force:true});}
});
test("denied encrypted backup prevents Keycloak client update and origin mutation",async()=>{
  const folder=await mkdtemp(join(tmpdir(),"oagent-port-guard-"));
  try{
    const password="b".repeat(48);
    const template=JSON.parse(await readFile(new URL(
      "../../../deploy/saas/free-pilot/oagent-realm.json",import.meta.url),"utf8"));
    await mkdir(join(folder,".private"));
    const settings="OAGENT_ORIGIN="+from+"\nOAGENT_OWNER_PASSWORD="+password+"\n";
    await writeFile(join(folder,".env.local"),settings);
    await writeFile(join(folder,"oagent-realm.json"),JSON.stringify(template));
    await writeFile(join(folder,".private","oagent-realm.json"),
      JSON.stringify(renderOwnerRealm(template,{origin:from,password}),null,2)+"\n");
    let updated=false;
    const remote=async args=>{
      if(args.includes("update"))updated=true;
      if(args.includes("get")){
        if(args.includes("clients"))return JSON.stringify([{id:clientId}]);
        return JSON.stringify(client);
      }
      return "";
    };
    await assert.rejects(()=>migrateExisting({apply:true,directory:folder,run:execute,
      remote,checkDb:async()=>({status:"already-matched"}),
      backup:async()=>{throw Error("no backup");},
      keyDirectory:join(folder,"keys"),backupDirectory:join(folder,"backups")}),/no backup/);
    assert.equal(updated,false);
    assert.equal(await readFile(join(folder,".env.local"),"utf8"),settings);
  }finally{await rm(folder,{recursive:true,force:true});}
});
