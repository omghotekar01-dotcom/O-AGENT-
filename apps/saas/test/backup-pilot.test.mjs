import test from "node:test";
import assert from "node:assert/strict";
import {Readable,Writable} from "node:stream";
import {mkdtemp,readFile,writeFile,rm} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {encryptBackup,decryptBackup,verifyBackup} from "../../../deploy/saas/free-pilot/backup-crypto.mjs";

test("zero-cost backups encrypt at rest, authenticate tag and refuse tampering",async()=>{
  const folder=await mkdtemp(join(tmpdir(),"oagent-crypt-"));
  try{
    const target=join(folder,"database.oagent.enc");
    const passphrase="very-long-unique-local-test-passphrase";
    const secret="SENSITIVE POSTGRES SQL TOKEN "+ "top secret".repeat(1000);
    await encryptBackup(Readable.from([Buffer.from(secret)]),target,passphrase);
    const raw=await readFile(target);
    assert.equal(raw.subarray(0,8).toString("utf8"),"OAGENTB1");
    assert.equal(raw.includes(Buffer.from("SENSITIVE POSTGRES")),false);
    assert.equal(await verifyBackup(target,passphrase),true);
    const output=[];
    await decryptBackup(target,passphrase,new Writable({
      write(chunk,_enc,callback){output.push(chunk);callback();}
    }));
    assert.equal(Buffer.concat(output).toString(),secret);
    await assert.rejects(()=>verifyBackup(target,
      "wrong-unique-backup-passphrase"),/authenticate|Unsupported state/);
    raw[raw.length-20]^=1;
    const tampered=join(folder,"tampered.oagent.enc");
    await writeFile(tampered,raw);
    await assert.rejects(()=>verifyBackup(tampered,passphrase),
      /authenticate|Unsupported state/);
    await assert.rejects(()=>encryptBackup(Readable.from([]),
      join(folder,"weak.oagent.enc"),"tiny"),/at least 20/);
  }finally{await rm(folder,{force:true,recursive:true});}
});
