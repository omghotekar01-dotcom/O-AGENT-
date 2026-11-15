import test from "node:test";
import assert from "node:assert/strict";
import {mkdtemp,rm} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {classifyPilotCluster,buildBootstrapSql,bootstrapPilotDb} from "../../../deploy/saas/free-pilot/bootstrap-db.mjs";

const secrets={oagent_runtime:"a".repeat(48),
  oagent_migrator:"b".repeat(48),oagent_keycloak:"c".repeat(48)};
const missing=classifyPilotCluster();
const safeRole=role=>[role,"t","f","f","f","f","f"];

test("partially initialized postgres volume has missing O-AGENT roles and databases",()=>{
  assert.deepEqual(missing.missingDatabases,["oagent","keycloak"]);
  assert.deepEqual(missing.missingRoles,["oagent_runtime","oagent_migrator","oagent_keycloak"]);
  assert.equal(missing.ready,false);
  const p=buildBootstrapSql(missing,secrets);
  assert.match(p.roleSql,/BEGIN;/);
  assert.match(p.roleSql,/CREATE ROLE oagent_migrator LOGIN NOSUPERUSER NOBYPASSRLS/);
  assert.deepEqual(p.dbSql,["CREATE DATABASE oagent OWNER oagent_migrator;",
    "CREATE DATABASE keycloak OWNER oagent_keycloak;"]);
  assert.match(p.schemaSql,/ALTER DEFAULT PRIVILEGES FOR ROLE oagent_migrator/);
  assert.doesNotMatch(JSON.stringify(p),/DROP DATABASE|DROP ROLE|TRUNCATE|DELETE FROM|REVOKE/);
});
test("database ownership mismatch and elevated existing roles are refused",()=>{
  assert.throws(()=>classifyPilotCluster({
    databaseRows:[["oagent","postgres"]]}),/different owner/);
  assert.throws(()=>classifyPilotCluster({roleRows:[
    ["oagent_runtime","t","t","f","f","f","f"]]}),/unsafe privileges/);
  assert.throws(()=>classifyPilotCluster({databaseRows:[
    ["oagent","oagent_migrator"]]}),/owner role is absent/);
});
test("read-only first-start diagnosis never backs up or changes PostgreSQL",async()=>{
  const r=await bootstrapPilotDb({inspect:async()=>missing,
    query:()=>{throw Error("unexpected SQL")},
    backup:()=>{throw Error("unexpected encrypted backup")}});
  assert.equal(r.status,"incomplete");
  assert.equal(r.missingRoles.length,3);
});
test("missing roles and databases are created only AFTER verified encrypted backup",async()=>{
  const folder=await mkdtemp(join(tmpdir(),"oagent-bootstrap-"));
  try{
    let state=missing;
    const calls=[];let backup=false,verified=false;
    const result=await bootstrapPilotDb({
      apply:true,read:async()=>Object.entries(secrets).map(([k,v])=>
        ({oagent_runtime:"OAGENT_RUNTIME_PASSWORD",
          oagent_migrator:"OAGENT_MIGRATION_PASSWORD",
          oagent_keycloak:"OAGENT_KEYCLOAK_DB_PASSWORD"}[k])+"="+v).join("\n")+"\n",
      inspect:async()=>state,
      backup:async()=>{backup=true;},
      verify:async()=>{assert.equal(backup,true);verified=true;return true;},
      query:async(args,{input})=>{
        assert.equal(verified,true,"no modification before encrypted backup verification");
        calls.push([args,input]);
        if(input.includes("ALTER DEFAULT PRIVILEGES")){
          state=classifyPilotCluster({databaseRows:[
            ["keycloak","oagent_keycloak"],["oagent","oagent_migrator"]],
            roleRows:["oagent_runtime","oagent_migrator","oagent_keycloak"].map(safeRole)});
        }
        return "";
      },
      keyDirectory:join(folder,"keys"),backupDirectory:join(folder,"backups"),
    });
    assert.equal(result.status,"bootstrapped");
    assert.equal(calls.length,5);
    assert.equal(calls[0][0][1],"postgres");
    assert.equal(calls.at(-1)[0][1],"oagent");
    assert.equal(result.createdRoles.length,3);
    assert.equal(result.createdDatabases.length,2);
  }finally{await rm(folder,{recursive:true,force:true});}
});
test("no SQL executes when cluster encryption or authentication fails",async()=>{
  const dir=await mkdtemp(join(tmpdir(),"oagent-bootstrap-refuse-"));
  try{
    await assert.rejects(()=>bootstrapPilotDb({apply:true,inspect:async()=>missing,
      read:async()=>["OAGENT_RUNTIME_PASSWORD="+secrets.oagent_runtime,
        "OAGENT_MIGRATION_PASSWORD="+secrets.oagent_migrator,
        "OAGENT_KEYCLOAK_DB_PASSWORD="+secrets.oagent_keycloak].join("\n"),
      backup:async()=>{throw Error("cluster backup failed")},
      query:()=>{throw Error("no SQL may execute")},
      keyDirectory:join(dir,"keys"),backupDirectory:join(dir,"backups")}),
    /cluster backup failed/);
  }finally{await rm(dir,{recursive:true,force:true});}
});
