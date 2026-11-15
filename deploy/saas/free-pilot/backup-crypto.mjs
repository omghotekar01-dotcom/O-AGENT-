import {createCipheriv,createDecipheriv,randomBytes,scryptSync} from "node:crypto";
import {createReadStream,createWriteStream} from "node:fs";
import {open,rm,stat} from "node:fs/promises";
import {once} from "node:events";
import {pipeline} from "node:stream/promises";
import {Writable} from "node:stream";

// AEAD, not obfuscation: salt(16), nonce(12), tag(16), streaming AES-256-GCM.
// The whole dump is encrypted BEFORE being persisted to disk.
const MAGIC=Buffer.from("OAGENTB1");
const HEADER_SIZE=36;
function key(password,salt){
  if(typeof password!=="string"||password.length<20)
    throw Error("Use a unique backup passphrase of at least 20 characters");
  return scryptSync(password,salt,32,{N:1<<15,maxmem:128*1024*1024});
}
export async function encryptBackup(source,destination,password){
  const salt=randomBytes(16),nonce=randomBytes(12),cipher=createCipheriv(
    "aes-256-gcm",key(password,salt),nonce);
  const sink=createWriteStream(destination,{flags:"wx",mode:0o600});
  try{
    const header=Buffer.concat([MAGIC,salt,nonce]);
    if(!sink.write(header))await once(sink,"drain");
    // Keep the stream open until the authenticated tag has been appended.
    await pipeline(source,cipher,sink,{end:false});
    sink.end(cipher.getAuthTag());
    await once(sink,"finish");
  }catch(error){
    sink.destroy();
    await rm(destination,{force:true});
    throw error;
  }
}
export async function decryptBackup(path,password,receiver){
  const file=await open(path,"r");
  let header,tag,size;
  try{
    size=(await file.stat()).size;
    if(size<HEADER_SIZE+16)throw Error("Backup too short or corrupted");
    header=Buffer.alloc(HEADER_SIZE);tag=Buffer.alloc(16);
    await file.read(header,0,HEADER_SIZE,0);
    await file.read(tag,0,16,size-16);
  }finally{await file.close();}
  if(!header.subarray(0,8).equals(MAGIC))
    throw Error("Unrecognized encrypted O-AGENT backup");
  const salt=header.subarray(8,24),nonce=header.subarray(24,36);
  const decipher=createDecipheriv("aes-256-gcm",key(password,salt),nonce);
  decipher.setAuthTag(tag);
  await pipeline(createReadStream(path,{start:HEADER_SIZE,end:size-17}),
    decipher,receiver);
}
export async function verifyBackup(path,password){
  const sink=new Writable({write(_chunk,_encoding,cb){cb();}});
  await decryptBackup(path,password,sink); // rejects wrong passphrase/tampering
  return true;
}
