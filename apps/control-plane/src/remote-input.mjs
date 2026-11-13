import { randomInt, timingSafeEqual } from "node:crypto";
import { DomainError } from "./core.mjs";

const PAIR_TTL = 2 * 60 * 1000;
const CONTROL_TTL = 20 * 60 * 1000;
const HEARTBEAT_TTL = 6000;
const MAX_QUEUE = 48;
const MIN_GAP = 30;
const CODE_PATTERN = /^[0-9]{8}$/;

function validateAction(input) {
  if (!input || typeof input !== "object" || Array.isArray(input))
    throw new DomainError(400, "Invalid remote input");
  const type = input.type;
  if (type === "move") {
    const dx = input.dx, dy = input.dy;
    if (!Number.isInteger(dx) || !Number.isInteger(dy) || Math.abs(dx) > 150 ||
        Math.abs(dy) > 150) throw new DomainError(400, "Pointer delta out of range");
    return { type, dx, dy };
  }
  if (type === "click") {
    if (!["left", "right", "double"].includes(input.button))
      throw new DomainError(400, "Invalid mouse button");
    return { type, button: input.button };
  }
  if (type === "scroll") {
    if (!Number.isInteger(input.steps) || input.steps < -3 || input.steps > 3 || input.steps === 0)
      throw new DomainError(400, "Invalid scroll amount");
    return { type, steps: input.steps };
  }
  if (type === "key") {
    if (!["enter", "escape", "backspace", "tab", "up", "down", "left", "right"].includes(input.key))
      throw new DomainError(400, "Unsupported key");
    return { type, key: input.key };
  }
  if (type === "text") {
    if (typeof input.text !== "string" || !input.text ||
        input.text.length > 300 || /[\u0000-\u0008\u000b-\u001f]/.test(input.text))
      throw new DomainError(400, "Text input must be 1 to 300 safe characters");
    return { type, text: input.text };
  }
  throw new DomainError(400, "Unsupported remote input action");
}

/** Fully ephemeral, owner-driven, physically paired remote input.
 * Nothing persists to disk or the O-AGENT activity feed. No input is accepted
 * without a fresh opted-in browser screen capture and paired Windows helper.
 */
export class RemoteInput {
  constructor({ now = () => Date.now(), captureFresh = () => false } = {}) {
    this.now = now;
    this.captureFresh = captureFresh;
    this.session = null;
  }
  current() {
    const s = this.session;
    if (!s) return null;
    if (this.now() >= s.expiresAt ||
        (s.active && this.now() - s.lastPoll > HEARTBEAT_TTL)) {
      this.session = null;
      return null;
    }
    return s;
  }
  status() {
    const s = this.current();
    return {
      supported: true, paired: !!s?.active,
      awaitingPairing: !!s && !s.active,
      workerId: s?.workerId ?? null,
      expiresAt: s?.active ? new Date(s.expiresAt).toISOString() : null,
      helperOnline: !!s && this.now() - s.lastPoll < HEARTBEAT_TTL,
      captureFresh: this.captureFresh(),
      requiresLocalPairing: true,
      mode: "explicit_windows_remote_input",
    };
  }
  prepare(workerId) {
    if (!this.captureFresh()) throw new DomainError(409,
      "Start a consented screen share before enabling remote input");
    if (typeof workerId !== "string" || !/^[a-zA-Z0-9_-]{1,100}$/.test(workerId))
      throw new DomainError(400, "Invalid worker ID");
    if (this.current()?.active) throw new DomainError(409,
      "A remote control session is already paired. Stop it first");
    const code = String(randomInt(0, 100000000)).padStart(8, "0");
    const now = this.now();
    this.session = { workerId, code, active: false, preparedAt: now,
      expiresAt: now + PAIR_TTL, lastPoll: now, lastAction: 0, queue: [] };
    // This code goes ONLY to the worker-token-authenticated LOCAL helper.
    return { pairingCode: code, expiresInSeconds: PAIR_TTL / 1000 };
  }
  pair(input) {
    const s = this.current();
    if (!s || s.active) throw new DomainError(409,
      "No pending Windows pairing request. Start the local remote-control companion");
    const code = input?.code;
    if (typeof code !== "string" || !CODE_PATTERN.test(code) ||
        !timingSafeEqual(Buffer.from(code), Buffer.from(s.code)))
      throw new DomainError(403, "Incorrect or expired pairing code");
    if (!this.captureFresh()) throw new DomainError(409,
      "The laptop must be actively sharing a selected screen");
    s.active = true;
    s.code = null;
    const now = this.now();
    s.expiresAt = now + CONTROL_TTL;
    s.lastPoll = now;
    return this.status();
  }
  next(workerId) {
    const s = this.current();
    if (!s || s.workerId !== workerId)
      throw new DomainError(409, "Remote input is not enabled for this Windows helper");
    s.lastPoll = this.now();
    if (!s.active || !this.captureFresh()) return { action: null, ...this.status() };
    return { action: s.queue.shift() ?? null, ...this.status() };
  }
  action(input) {
    const s = this.current();
    if (!s?.active || !this.captureFresh())
      throw new DomainError(409, "Remote input unavailable. Pair the visible Windows helper and share the screen");
    const now = this.now();
    if (now - s.lastPoll >= HEARTBEAT_TTL)
      throw new DomainError(409, "Windows input helper disconnected");
    if (now - s.lastAction < MIN_GAP) throw new DomainError(429, "Remote input rate limit");
    if (s.queue.length >= MAX_QUEUE) throw new DomainError(429, "Windows input queue full");
    const value = validateAction(input);
    s.queue.push(value);
    s.lastAction = now;
    return { accepted: true };
  }
  stop(workerId = null) {
    const s = this.current();
    if (workerId != null && s && s.workerId !== workerId)
      throw new DomainError(403, "Incorrect Windows helper");
    this.session = null;
    return this.status();
  }
}
