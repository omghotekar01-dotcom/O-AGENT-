import test from "node:test";
import assert from "node:assert/strict";
import {mkdtemp,rm} from "node:fs/promises";
import {join} from "node:path";
import {tmpdir} from "node:os";
import {createHash,createHmac,pbkdf2Sync} from "node:crypto";
import {parseRoleSecrets,matchesRolePassword,repairDbAuth} from "../../../deploy/saas/free-pilot/repair-db-auth.mjs";

const source=["OAGENT_RUNTIME_PASSWORD="+ "a".repeat(48),
  "OAGENT_MIGRATION_PASSWORD="+ "b".repeat(48),
  "OAGENT_KEYCLOAK_DB_PASSWORD="+ "c".repeat(48)].join("\n")+"\n";
function md5(password,role){
  return "md5"+createHash("md5").update(password+role).digest("hex");
}
function scram(password){
  const salt=Buffer.from("static-test-salt");
  const rounds=4096;
  const salted=pbkdf2Sync(password,salt,rounds,32,"sha256");
  const client=createHmac("sha256",salted).update("Client Key").digest();
  const stored=createHash("sha256").update(client).digest("base64");
  const server=createHmac("sha256",salted).update("Server Key").digest("base64");
  return "SCRAM-SHA-256$"+rounds+":"+salt.toString("base64")+"$"+stored+":"+server;
}
test("role password verification supports PostgreSQL SCRAM and MD5 without revealing passwords",()=>{
  const roles=parseRoleSecrets(source);
  assert.equal(matchesRolePassword(roles.oagent_migrator,"oagent_migrator",
    scram(roles.oagent_migrator)),true);
  assert.equal(matchesRolePassword(roles.oagent_runtime,"oagent_runtime",
    md5(roles.oagent_runtime,"oagent_runtime")),true);
  assert.equal(matchesRolePassword("wrong","oagent_migrator",scram(roles.oagent_migrator)),false);
  assert.equal(matchesRolePassword(roles.oagent_runtime,"oagent_runtime","unknown-hash"),false);
  assert.throws(()=>parseRoleSecrets("OAGENT_MIGRATION_PASSWORD=weak"),/role secret/);
});
test("read-only diagnostic never rotates roles or writes backups",async()=>{
  const roles=parseRoleSecrets(source);
  const stored=Object.fromEntries(Object.entries(roles).map(([name,pwd])=>
    [name,md5(pwd,name)]));
  stored.oagent_migrator=md5("old-password","oagent_migrator");
  const result=await repairDbAuth({apply:false,read:async()=>source,
    inspect:async()=>stored,backup:()=>{throw Error("backup must not run")},
    query:()=>{throw Error("query must not run")}});
  assert.deepEqual(result.roles,["oagent_migrator"]);
  assert.equal(result.status,"needs-repair");
  assert.equal(result.changed,0);
});
test("repair enforces backup verification before sending SQL credentials over stdin",async()=>{
  const tmp=await mkdtemp(join(tmpdir(),"oagent-auth-repair-"));
  try{
    const roles=parseRoleSecrets(source);
    const hashes=Object.fromEntries(Object.entries(roles).map(([name,pwd])=>
      [name,md5(pwd,name)]));
    hashes.oagent_migrator=md5("old-password","oagent_migrator");
    let backedUp=false,verified=0,rotated=false;
    const query=async sql=>{
      assert.equal(backedUp,true,"no SQL modification before backup");
      assert.equal(verified,2,"both encrypted archives must verify first");
      assert.match(sql,/BEGIN;\nALTER ROLE oagent_migrator PASSWORD /);
      assert.doesNotMatch(sql,/ALTER ROLE oagent_keycloak/);
      rotated=true;
      hashes.oagent_migrator=md5(roles.oagent_migrator,"oagent_migrator");
    };
    const result=await repairDbAuth({apply:true,read:async()=>source,
      inspect:async()=>hashes,query,
      backup:async()=>{backedUp=true;},verify:async()=>{verified++;return true;},
      keyDirectory:join(tmp,"keys"),backupDirectory:join(tmp,"backups")});
    assert.equal(result.changed,1);
    assert.equal(result.status,"repaired");
    assert.equal(rotated,true);
    assert.match(result.keyPath,/\.key$/);
  }finally{await rm(tmp,{recursive:true,force:true});}
});
test("failure to produce an encrypted backup refuses every database credential change",async()=>{
  const roles=parseRoleSecrets(source);
  const hashes=Object.fromEntries(Object.entries(roles).map(([name,pwd])=>
    [name,md5(pwd,name)]));
  hashes.oagent_migrator=md5("old-password","oagent_migrator");
  const tmp=await mkdtemp(join(tmpdir(),"oagent-no-backup-"));
  try{
    await assert.rejects(()=>repairDbAuth({apply:true,read:async()=>source,
      inspect:async()=>hashes,
      query:()=>{throw Error("unsafe SQL executed")},
      backup:async()=>{throw Error("backup failed")},
      keyDirectory:join(tmp,"keys"),backupDirectory:join(tmp,"backups")
    }),/backup failed/);
  }finally{await rm(tmp,{recursive:true,force:true});}
});
