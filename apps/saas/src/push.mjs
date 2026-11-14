import {createHash} from "node:crypto";
import webpush from "web-push";
import {withTenant} from "./store.mjs";
import {httpError} from "./operations.mjs";

// Never turn a user-submitted push endpoint into a server-side request to
// arbitrary internal URLs. Only recognized browser push hosts are supported.
const HOSTS=new Set([
  "fcm.googleapis.com","updates.push.services.mozilla.com",
  "push.services.mozilla.com","web.push.apple.com",
  "api.push.apple.com",
]);
export function validatePushSubscription(value){
  const endpoint=value?.endpoint;
  if(typeof endpoint!=="string"||endpoint.length<30||endpoint.length>2000)
    throw httpError(400,"Invalid push subscription");
  let address;
  try{address=new URL(endpoint);}catch{throw httpError(400,"Invalid push endpoint URL");}
  if(address.protocol!=="https:"||address.username||address.password||
      address.port||address.hash||!HOSTS.has(address.hostname.toLowerCase()))
    throw httpError(400,"Unsupported browser push service endpoint");
  const p256dh=value?.keys?.p256dh,auth=value?.keys?.auth;
  if(typeof p256dh!=="string"||!/^[A-Za-z0-9_-]{85,100}$/.test(p256dh)||
     typeof auth!=="string"||!/^[A-Za-z0-9_-]{18,30}$/.test(auth))
    throw httpError(400,"Invalid browser push encryption keys");
  return {endpoint,keys:{p256dh,auth}};
}
const hashEndpoint=endpoint=>createHash("sha256").update(endpoint).digest();
export async function registerPush(client,tenantId,body){
  const data=validatePushSubscription(body);
  const digest=hashEndpoint(data.endpoint);
  const existing=await client.query(
    "SELECT id FROM push_subscriptions WHERE endpoint_hash=$1",[digest]);
  if(!existing.rows[0]){
    const count=await client.query(
      "SELECT count(*)::int AS count FROM push_subscriptions");
    if(count.rows[0].count>=5)
      throw httpError(429,"Maximum five phone/browser subscriptions per account");
  }
  const saved=await client.query(
    "INSERT INTO push_subscriptions(tenant_id,endpoint_hash,endpoint,auth_key,p256dh_key) VALUES($1,$2,$3,$4,$5) ON CONFLICT (tenant_id,endpoint_hash) DO UPDATE SET auth_key=EXCLUDED.auth_key,p256dh_key=EXCLUDED.p256dh_key RETURNING tenant_id",
    [tenantId,digest,data.endpoint,data.keys.auth,data.keys.p256dh]);
  if(!saved.rowCount)throw httpError(409,"Push subscription could not be saved");
  return {subscribed:true};
}
export async function unregisterPush(client,endpoint){
  if(typeof endpoint!=="string"||endpoint.length<30||endpoint.length>2000)
    throw httpError(400,"Invalid push endpoint");
  await client.query("DELETE FROM push_subscriptions WHERE endpoint_hash=$1",
    [hashEndpoint(endpoint)]);
  return {subscribed:false};
}
export async function pushStatus(client){
  const {rows}=await client.query(
    "SELECT count(*)::int AS count FROM push_subscriptions");
  return {subscribedDevices:rows[0].count};
}
export async function notifyTenant(pool,tenantId,config,{send=webpush.sendNotification}={}){
  if(!config.push)return {enabled:false,sent:0};
  const subscriptions=await withTenant(pool,tenantId,async client=>{
    const {rows}=await client.query(
      "SELECT endpoint_hash,endpoint,auth_key,p256dh_key FROM push_subscriptions ORDER BY created_at DESC LIMIT 5");
    return rows;
  });
  let sent=0;
  // Never include prompts, filenames, tokens, tenant IDs or tool arguments on
  // a phone lock screen. Owner must authenticate to review exact permissions.
  const payload=JSON.stringify({type:"approval",title:"O-AGENT approval needed",
    body:"Open your private command center to review a request",
    url:"/?view=approvals"});
  for(const sub of subscriptions){
    try{
      await send({endpoint:sub.endpoint,keys:{
        auth:sub.auth_key,p256dh:sub.p256dh_key,
      }},payload,{vapidDetails:{
        subject:config.publicOrigin,
        publicKey:config.push.publicKey,
        privateKey:config.push.privateKey,
      },TTL:90,timeout:5000});
      sent++;
    }catch(error){
      if(error?.statusCode===404||error?.statusCode===410)
        await withTenant(pool,tenantId,c=>c.query(
          "DELETE FROM push_subscriptions WHERE endpoint_hash=$1",
          [sub.endpoint_hash]));
      // Do not reveal subscription URLs or push-provider response bodies in logs.
    }
  }
  return {enabled:true,sent};
}
