import { createSign, randomUUID } from "node:crypto";
import { DomainError } from "./core.mjs";

function urlBase64(value) {
  return Buffer.from(value).toString("base64url");
}
const MAX_DEVICES = 5;
export class PushHub {
  constructor(core, accounts, {
    env = process.env, fetchImpl = fetch, now = () => Date.now(),
  } = {}) {
    this.core = core;
    this.accounts = accounts;
    this.fetchImpl = fetchImpl;
    this.now = now;
    this.data = core.data.accounts.pushDevices ??= {};
    this.accessToken = null;
    this.tokenExpiresAt = 0;
    this.service = null;
    if (env.OAGENT_FCM_SERVICE_ACCOUNT_BASE64) {
      try {
        const candidate = JSON.parse(
          Buffer.from(env.OAGENT_FCM_SERVICE_ACCOUNT_BASE64, "base64").toString("utf8"));
        if (/^[a-z][a-z0-9-]{4,100}$/.test(candidate.project_id) &&
            typeof candidate.client_email === "string" &&
            candidate.client_email.endsWith(".gserviceaccount.com") &&
            typeof candidate.private_key === "string" &&
            candidate.private_key.includes("BEGIN PRIVATE KEY")) {
          this.service = candidate;
        }
      } catch { /* Unsafe or malformed configuration stays disabled. */ }
    }
    this.unsub = core.subscribe(event => {
      // The event bus never waits on external Firebase requests. All payloads
      // intentionally omit prompts, filenames, tool arguments and secrets.
      void this._dispatch(event).catch(() => {});
    });
  }
  enabled() { return !!this.service && !!this.accounts.master; }
  status(userId) {
    return {
      configured: this.enabled(),
      devices: (this.data[userId] ?? []).map(x => ({
        id: x.id, platform: x.platform, label: x.label, registeredAt: x.registeredAt,
      })),
    };
  }
  register(userId, body = {}) {
    if (!this.enabled()) throw new DomainError(503,
      "Push notifications need a configured Firebase service account and encrypted vault");
    const token = body.token;
    if (typeof token !== "string" || token.length < 50 ||
        token.length > 4096 || /\s/.test(token))
      throw new DomainError(400, "Invalid Firebase device registration token");
    const platform = body.platform;
    if (!["android", "ios"].includes(platform))
      throw new DomainError(400, "Unsupported push platform");
    const label = typeof body.label === "string" &&
      body.label.length <= 80 ? body.label : platform;
    const saved = this.data[userId] ??= [];
    // Prevent accidental duplication on token refresh without returning token.
    for (const device of saved) {
      if (this.accounts.decrypt(userId, "pushDevice", device.secret) === token)
        return this.status(userId);
    }
    if (saved.length >= MAX_DEVICES)
      throw new DomainError(409, "Device limit reached; revoke one first");
    const id = randomUUID();
    saved.push({ id, platform, label,
      registeredAt: new Date(this.now()).toISOString(),
      secret: this.accounts.encrypt(userId, "pushDevice", token) });
    this.core.commit("push.device.registered", { userId, deviceId:id });
    return this.status(userId);
  }
  unregister(userId, id) {
    if (typeof id !== "string" || !/^[0-9a-f-]{36}$/.test(id))
      throw new DomainError(400, "Invalid notification device ID");
    const saved = this.data[userId] ?? [];
    const before = saved.length;
    this.data[userId] = saved.filter(x => x.id !== id);
    if (before === this.data[userId].length)
      throw new DomainError(404, "Notification device not found");
    this.core.commit("push.device.revoked", { userId, deviceId:id });
    return this.status(userId);
  }
  async _oauthToken() {
    if (!this.service) throw new DomainError(503,"Firebase is not configured");
    if (this.accessToken && this.now() < this.tokenExpiresAt - 120000)
      return this.accessToken;
    const now = Math.floor(this.now() / 1000);
    const header = urlBase64(JSON.stringify({ alg:"RS256", typ:"JWT" }));
    const payload = urlBase64(JSON.stringify({
      iss:this.service.client_email,
      sub:this.service.client_email,
      aud:"https://oauth2.googleapis.com/token",
      scope:"https://www.googleapis.com/auth/firebase.messaging",
      iat:now,exp:now+3300,
    }));
    const content = header+"."+payload;
    const signer = createSign("RSA-SHA256");
    signer.update(content);
    signer.end();
    const assertion = content+"."+
      signer.sign(this.service.private_key).toString("base64url");
    const response = await this.fetchImpl("https://oauth2.googleapis.com/token",{
      method:"POST",
      headers:{"Content-Type":"application/x-www-form-urlencoded"},
      body:new URLSearchParams({
        grant_type:"urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion,
      }).toString(),
      signal:AbortSignal.timeout(13000),redirect:"error",
    });
    if (!response.ok) throw new DomainError(503,
      "Firebase OAuth rejected server credentials");
    const data = await response.json();
    if (typeof data.access_token !== "string" || data.access_token.length < 20)
      throw new DomainError(503,"Firebase OAuth returned no access token");
    this.accessToken = data.access_token;
    this.tokenExpiresAt = this.now() + Math.min(
      Number.isFinite(data.expires_in) ? data.expires_in : 3000,3300)*1000;
    return this.accessToken;
  }
  async _deliver(device, userId, type, taskId) {
    const key = this.accounts.decrypt(userId,"pushDevice",device.secret);
    const access = await this._oauthToken();
    const title = type === "approval" ? "O-AGENT needs approval" : "O-AGENT agent update";
    const body = type === "approval"
      ? "Open your workspace to review the exact requested action."
      : "An enrolled agent reported a status change.";
    const response = await this.fetchImpl(
      "https://fcm.googleapis.com/v1/projects/"+this.service.project_id+
      "/messages:send",{
        method:"POST",redirect:"error",signal:AbortSignal.timeout(13000),
        headers:{Authorization:"Bearer "+access,"Content-Type":"application/json"},
        body:JSON.stringify({message:{
          token:key,notification:{title,body},
          data:{type,taskId:taskId??"",route:"remote"},
          android:{priority:"high"},
          apns:{headers:{"apns-priority":"10"},payload:{aps:{sound:"default"}}},
        }}),
      });
    if (!response.ok) throw new DomainError(503,
      "Firebase rejected push delivery"); // never log provider error body
  }
  async _dispatch(event) {
    if (!this.enabled()) return;
    let userId, type, taskId = "";
    if (event.type === "task.waiting_for_approval" ||
        event.type === "codex.approval.requested") {
      userId = "owner"; type = "approval"; taskId = event.taskId || "";
    } else if (event.type === "account.cursor.run.requested" ||
        event.type === "account.cursor.run.cancelled" ||
        event.type === "account.cursor.created") {
      userId = event.userId; type = "update";
    } else return;
    if (!userId) return;
    const devices = (this.data[userId] ?? []).slice(0,MAX_DEVICES);
    await Promise.allSettled(devices.map(d => this._deliver(d,userId,type,taskId)));
  }
}
