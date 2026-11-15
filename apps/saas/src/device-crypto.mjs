import {createHash, createPublicKey, sign, verify,
  generateKeyPairSync, randomBytes} from "node:crypto";

const unauthorized = () => Object.assign(Error("Device authentication failed"),{status:401});
export const sha256 = data=>createHash("sha256").update(data).digest();
export const hexSha256 = data=>sha256(data).toString("hex");

export function parseEd25519PublicKey(pem) {
  if(typeof pem!=="string" || pem.length>800 || pem.length<80)
    throw Object.assign(Error("Invalid device public key"),{status:400});
  try {
    const key=createPublicKey(pem);
    if(key.asymmetricKeyType!=="ed25519")
      throw Error("Wrong key type");
    return key.export({type:"spki",format:"der"});
  }catch {
    throw Object.assign(Error("Invalid Ed25519 device key"),{status:400});
  }
}
export function generateDeviceKeys() {
  const {publicKey,privateKey}=generateKeyPairSync("ed25519");
  return {publicKeyPem:publicKey.export({format:"pem",type:"spki"}),
    privateKeyPem:privateKey.export({format:"pem",type:"pkcs8"})};
}
export function canonicalRequest({method,path,timestamp,nonce,rawBody=Buffer.alloc(0)}) {
  if(typeof method!=="string"||!method||typeof path!=="string"||
      !path.startsWith("/")||typeof nonce!=="string")
    throw Error("Invalid canonical request");
  return Buffer.from(["oagent-device-v1",method.toUpperCase(),path,
    String(timestamp),nonce,hexSha256(rawBody)].join("\n"),"utf8");
}
export function deviceHeaders(privateKeyPem,{deviceId,method,path,
  rawBody=Buffer.alloc(0),now=Date.now,nonce=randomBytes(24).toString("base64url")}) {
  const timestamp=now();
  return {
    "x-oagent-device-id":deviceId,
    "x-oagent-timestamp":String(timestamp),
    "x-oagent-nonce":nonce,
    "x-oagent-signature":sign(null,canonicalRequest({
      method,path,timestamp,nonce,rawBody}),privateKeyPem).toString("base64url"),
  };
}
/** Authentication and anti-replay are verified BEFORE any tenant transaction. */
export async function verifyDeviceHeaders(pool,{headers,method,path,rawBody,now=Date.now}) {
  const id=headers["x-oagent-device-id"];
  const nonce=headers["x-oagent-nonce"];
  const timestampString=headers["x-oagent-timestamp"];
  const signature=headers["x-oagent-signature"];
  const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  if(typeof id!=="string"||!uuid.test(id) ||
     typeof nonce!=="string"||!/^[A-Za-z0-9_-]{20,100}$/.test(nonce)||
     typeof timestampString!=="string"||!/^\d{13}$/.test(timestampString)||
     typeof signature!=="string"||!/^[A-Za-z0-9_-]{80,150}$/.test(signature))
    throw unauthorized();
  const timestamp=Number(timestampString);
  if(Math.abs(now()-timestamp)>120000)throw unauthorized();
  const {rows}=await pool.query(
    "SELECT device_id,tenant_id,public_key FROM device_auth_keys WHERE device_id=$1 AND revoked_at IS NULL",[id]);
  const found=rows[0];
  if(!found)throw unauthorized();
  let valid=false;
  try {
    const pub=createPublicKey({key:found.public_key,format:"der",type:"spki"});
    valid=verify(null,canonicalRequest({method,path,timestamp,nonce,rawBody}),
      pub,Buffer.from(signature,"base64url"));
  }catch{}
  if(!valid)throw unauthorized();
  // Unique database constraint prevents replay across instances/restarts.
  const used=await pool.query(
    "INSERT INTO device_replay_nonces(device_id,nonce,expires_at) VALUES($1,$2,now()+interval '5 minutes') ON CONFLICT DO NOTHING RETURNING nonce",
    [id,nonce]);
  if(used.rowCount!==1)throw unauthorized();
  // Expired nonces can be deleted by a periodic retention job.
  return {deviceId:found.device_id,tenantId:found.tenant_id};
}
