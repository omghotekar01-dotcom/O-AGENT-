import { randomBytes, randomUUID, createHash, scrypt as scryptCallback, timingSafeEqual } from "node:crypto";
import { promisify } from "node:util";
import { DomainError } from "./core.mjs";

const scrypt = promisify(scryptCallback);
const sha = value => createHash("sha256").update(value).digest("hex");
const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const code = kind => kind + "_" + randomBytes(32).toString("base64url");
const equal = (a, b) => {
  if (typeof a !== "string" || typeof b !== "string" || a.length !== b.length) return false;
  return timingSafeEqual(Buffer.from(a), Buffer.from(b));
};
const passwordValid = password => typeof password === "string" && password.length >= 12 &&
  password.length <= 128 && !/^\s|\s$/.test(password);
const normalizeEmail = value => typeof value === "string" ? value.trim().toLowerCase() : "";

export class PublicAuth {
  constructor(core, { env = process.env, fetchImpl = fetch, now = () => Date.now() } = {}) {
    this.core = core;
    this.env = env;
    this.fetchImpl = fetchImpl;
    this.now = now;
    core.data.accounts ??= {};
    core.data.accounts.members ??= {};
    core.data.accounts.sessions ??= {};
    this.accounts = core.data.accounts;
    this.rate = new Map();
    this.pendingRegistrations = new Set();
  }

  get enabled() {
    return this.env.OAGENT_PUBLIC_ACCOUNTS === "1" &&
      !!this.env.OAGENT_RESEND_API_KEY && !!this.env.OAGENT_MAIL_FROM &&
      /^https:\/\//.test(this.env.OAGENT_PUBLIC_URL || "");
  }
  config() {
    return { enabled: this.enabled, emailVerification: true, passwordRecovery: this.enabled,
      message: this.enabled ? "Email verification is required." :
      "Public signup is disabled until cloud HTTPS URL and email delivery are configured." };
  }
  requireEnabled() {
    if (!this.enabled) throw new DomainError(503, "Public accounts require HTTPS, email delivery and server configuration");
  }
  throttle(ip, action) {
    const key = String(ip).slice(0, 80) + ":" + action;
    const now = this.now();
    if (this.rate.size > 5000) for (const [k, v] of this.rate) if (v.until < now) this.rate.delete(k);
    const item = this.rate.get(key);
    const hits = item && item.until > now ? item.hits + 1 : 1;
    this.rate.set(key, { hits, until: item && item.until > now ? item.until : now + 15 * 60_000 });
    if (hits > (action === "login" ? 12 : 6)) throw new DomainError(429, "Too many requests. Try again later.");
  }
  find(email) {
    return Object.values(this.accounts.members).find(m => m.email === email && !m.revokedAt);
  }
  async passwordHash(password, salt) {
    return (await scrypt(password, Buffer.from(salt, "base64"), 64, { N: 16384, r: 8, p: 1 })).toString("base64");
  }
  async sendMail(to, subject, body) {
    const response = await this.fetchImpl("https://api.resend.com/emails", {
      method: "POST", signal: AbortSignal.timeout(15000),
      headers: { authorization: "Bearer " + this.env.OAGENT_RESEND_API_KEY,
        "content-type": "application/json" },
      body: JSON.stringify({ from: this.env.OAGENT_MAIL_FROM, to: [to], subject, text: body }),
    }).catch(() => null);
    if (!response?.ok) throw new DomainError(503, "Verification email unavailable. Contact the workspace administrator.");
  }
  async register({ email, displayName, password } = {}) {
    this.requireEnabled();
    const normalized = normalizeEmail(email);
    if (!emailPattern.test(normalized) || normalized.length > 254 ||
        typeof displayName !== "string" || !displayName.trim() || displayName.length > 80 ||
        !passwordValid(password)) throw new DomainError(400, "Enter a valid email, name and password of 12–128 characters");
    if (this.find(normalized) || this.pendingRegistrations.has(normalized)) throw new DomainError(409, "Account already exists. Sign in or recover your password.");
    const id = randomUUID();
    const salt = randomBytes(24).toString("base64");
    const verifyCode = code("verify");
    const member = {
      id, email: normalized, displayName: displayName.trim(), passwordSalt: salt,
      passwordHash: await this.passwordHash(password, salt), verifiedAt: null,
      verifyDigest: sha(verifyCode), verifyExpiresAt: this.now() + 15 * 60_000,
      createdAt: this.now(),
    };
    // Email before persisting: no unusable account is created if delivery fails.
    this.pendingRegistrations.add(normalized);
    try {
      await this.sendMail(normalized, "Verify your O-AGENT account",
        "Your O-AGENT verification code (valid 15 minutes):\n\n" + verifyCode +
        "\n\nOpen O-AGENT and enter the code under Verify email. Ignore if you did not sign up.");
      this.accounts.members[id] = member;
      this.core.commit("account.public.registered", { memberId: id });
      return { ok: true, message: "Verification code sent. Enter it in the app." };
    } finally {
      this.pendingRegistrations.delete(normalized);
    }
  }
  async resend({ email } = {}) {
    this.requireEnabled();
    const member = this.find(normalizeEmail(email));
    if (member && !member.verifiedAt &&
        (!member.verifyResentAt || this.now() - member.verifyResentAt > 60_000)) {
      const verification = code("verify");
      await this.sendMail(member.email, "Verify your O-AGENT account",
        "Your new O-AGENT verification code (valid 15 minutes):\n\n" + verification);
      member.verifyDigest = sha(verification);
      member.verifyExpiresAt = this.now() + 15 * 60_000;
      member.verifyResentAt = this.now();
      this.core.commit("account.public.verification.resent", { memberId: member.id });
    }
    return { ok: true, message: "If verification is pending, a new code has been sent." };
  }

  verify({ email, code: provided } = {}) {
    this.requireEnabled();
    const member = this.find(normalizeEmail(email));
    if (!member || member.verifiedAt || member.verifyExpiresAt <= this.now() ||
        !equal(sha(String(provided || "")), member.verifyDigest || "")) {
      throw new DomainError(400, "Verification code invalid or expired");
    }
    member.verifiedAt = this.now();
    delete member.verifyDigest;
    delete member.verifyExpiresAt;
    this.core.commit("account.public.verified", { memberId: member.id });
    return { ok: true };
  }
  createSession(member) {
    const token = code("oau");
    const digest = sha(token);
    this.accounts.sessions[digest] = { userId: member.id, createdAt: this.now(),
      expiresAt: this.now() + 30 * 24 * 60 * 60_000 };
    this.core.commit("account.session.created", { memberId: member.id });
    return { token, user: { id: member.id, displayName: member.displayName, role: "member" },
      expiresAt: this.accounts.sessions[digest].expiresAt };
  }
  authenticate(token) {
    if (typeof token !== "string" || token.length < 40 || token.length > 200) return null;
    const session = this.accounts.sessions[sha(token)];
    if (!session || session.expiresAt <= this.now()) return null;
    const member = this.accounts.members[session.userId];
    if (!member || member.revokedAt || !member.verifiedAt) return null;
    return { id: member.id, displayName: member.displayName, role: "member" };
  }
  async login({ email, password } = {}) {
    this.requireEnabled();
    const member = this.find(normalizeEmail(email));
    if (typeof password !== "string" || password.length > 128) {
      throw new DomainError(401, "Invalid email or password, or email not verified");
    }
    // Keep the expensive password hash path for unknown emails to reduce timing leaks.
    const hashed = await this.passwordHash(password, member?.passwordSalt ||
      Buffer.alloc(24).toString("base64"));
    if (!member?.verifiedAt || !equal(hashed, member.passwordHash)) {
      throw new DomainError(401, "Invalid email or password, or email not verified");
    }
    return this.createSession(member);
  }
  async forgot({ email } = {}) {
    this.requireEnabled();
    const member = this.find(normalizeEmail(email));
    if (member?.verifiedAt && (!member.recoveryAt || this.now() - member.recoveryAt > 60_000)) {
      const resetCode = code("reset");
      await this.sendMail(member.email, "Reset your O-AGENT password",
        "Your O-AGENT password reset code (valid 15 minutes):\n\n" + resetCode +
        "\n\nEnter it in the app. Ignore if you did not request this.");
      member.resetDigest = sha(resetCode);
      member.resetExpiresAt = this.now() + 15 * 60_000;
      member.recoveryAt = this.now();
      this.core.commit("account.password.reset.requested", { memberId: member.id });
    }
    return { ok: true, message: "If the account exists, a recovery email has been sent." };
  }
  async reset({ email, code: provided, newPassword } = {}) {
    this.requireEnabled();
    if (!passwordValid(newPassword)) throw new DomainError(400, "Use a password between 12 and 128 characters");
    const member = this.find(normalizeEmail(email));
    if (!member?.verifiedAt || !member.resetDigest ||
        member.resetExpiresAt <= this.now() ||
        !equal(sha(String(provided || "")), member.resetDigest)) {
      throw new DomainError(400, "Recovery code invalid or expired");
    }
    member.passwordSalt = randomBytes(24).toString("base64");
    member.passwordHash = await this.passwordHash(newPassword, member.passwordSalt);
    delete member.resetDigest; delete member.resetExpiresAt;
    for (const [digest, session] of Object.entries(this.accounts.sessions)) {
      if (session.userId === member.id) delete this.accounts.sessions[digest];
    }
    this.core.commit("account.password.reset.completed", { memberId: member.id });
    return { ok: true, message: "Password changed. All previous sessions were revoked." };
  }
  logout(token) {
    const digest = sha(token);
    if (this.accounts.sessions[digest]) {
      const memberId = this.accounts.sessions[digest].userId;
      delete this.accounts.sessions[digest];
      this.core.commit("account.session.revoked", { memberId });
    }
    return { ok: true };
  }
  revokeUser(memberId) {
    for (const [digest, session] of Object.entries(this.accounts.sessions)) {
      if (session.userId === memberId) delete this.accounts.sessions[digest];
    }
  }
}
