import { randomInt, timingSafeEqual } from "node:crypto";
import { DomainError } from "./core.mjs";

const PAIR_TTL = 2 * 60 * 1000;
const CONTROL_TTL = 20 * 60 * 1000;
const TRUSTED_IDLE_TTL = 12 * 60 * 60 * 1000;
const HEARTBEAT_TTL = 6000;
const MAX_QUEUE = 48;
const MIN_GAP = 18;
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
  if (type === "tap") {
    if (!Number.isSafeInteger(input.x) || !Number.isSafeInteger(input.y) ||
        input.x < 0 || input.x > 10000 ||
        input.y < 0 || input.y > 10000 ||
        !["left","right","double"].includes(input.button))
      throw new DomainError(400, "Tap coordinates or button invalid");
    return {type,x:input.x,y:input.y,button:input.button};
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
  if (type === "shortcut") {
    if (!["copy","paste","cut","undo","redo","select_all","save","find"].includes(input.name))
      throw new DomainError(400, "Unsupported keyboard shortcut");
    return {type,name:input.name};
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
  constructor({ now = () => Date.now(), captureFresh = () => false,
      captureDisplay = () => false } = {}) {
    this.now = now;
    this.captureFresh = captureFresh;
    this.captureDisplay = captureDisplay;
    this.session = null;
  }
  current() {
    const s = this.session;
    if (!s) return null;
    const now = this.now();
    // A trusted laptop must remain locally running and visibly opted in.
    // Stopping its helper revokes the capability, even when idle.
    if ((s.trusted || s.active) && now - s.lastPoll > HEARTBEAT_TTL) {
      this.session = null;
      return null;
    }
    if (now >= s.expiresAt) {
      if (!s.trusted || !s.active) {
        this.session = null;
        return null;
      }
      // A 20-minute control lease expires into view-only. The local helper
      // stays ready for another explicitly requested owner session.
      this.pause(s);
      s.expiresAt = now + TRUSTED_IDLE_TTL;
    }
    return s;
  }
  pause(s) {
    s.active = false;
    s.queue = [];
    s.dispatched = null;
    s.lastResult = null;
    s.lastAction = 0;
  }
  status() {
    const s = this.current();
    return {
      supported: true, paired: !!s?.active,
      awaitingPairing: !!s && !s.active && !s.trusted,
      trustedReady: !!s?.trusted && !s.active &&
        this.now() - s.lastPoll < HEARTBEAT_TTL,
      trustedMode: !!s?.trusted,
      workerId: s?.workerId ?? null,
      expiresAt: s?.active ? new Date(s.expiresAt).toISOString() : null,
      helperOnline: !!s && this.now() - s.lastPoll < HEARTBEAT_TTL,
      captureFresh: this.captureFresh(),
      requiresLocalPairing: !s?.trusted,
      mode: s?.trusted ? "locally_enrolled_one_tap_input" :
        "explicit_windows_remote_input",
      queueDepth: s?.queue.length ?? 0,
      lastInputResult: s?.lastResult ?? null,
    };
  }
  prepare(workerId, {trusted = false} = {}) {
    if (typeof trusted !== "boolean") throw new DomainError(400, "Invalid control mode");
    if (!trusted && !this.captureFresh()) throw new DomainError(409,
      "Start a consented screen share before enabling remote input");
    if (typeof workerId !== "string" || !/^[a-zA-Z0-9_-]{1,100}$/.test(workerId))
      throw new DomainError(400, "Invalid worker ID");
    if (this.current()?.active) throw new DomainError(409,
      "A remote control session is already paired. Stop it first");
    const code = trusted ? null :
      String(randomInt(0, 100000000)).padStart(8, "0");
    const now = this.now();
    this.session = { workerId, code, trusted, active: false, preparedAt: now,
      expiresAt: now + (trusted ? TRUSTED_IDLE_TTL : PAIR_TTL),
      lastPoll: now, lastAction: 0,
      failedPairAttempts: 0, queue: [], nextId: 0,
      dispatched: null, lastResult: null };
    // This code goes ONLY to the worker-token-authenticated LOCAL helper.
    return trusted
      ? { ready: true, trustedMode: true, requiresOwnerActivation: true }
      : { pairingCode: code, expiresInSeconds: PAIR_TTL / 1000 };
  }
  pair(input) {
    const s = this.current();
    if (!s || s.active || s.trusted) throw new DomainError(409,
      "No pending Windows pairing request. Start the local remote-control companion");
    const code = input?.code;
    if (typeof code !== "string" || !CODE_PATTERN.test(code) ||
        !timingSafeEqual(Buffer.from(code), Buffer.from(s.code))) {
      s.failedPairAttempts += 1;
      if (s.failedPairAttempts >= 5) this.session = null;
      throw new DomainError(403, "Incorrect pairing code. Five failures revoke the code");
    }
    if (!this.captureFresh()) throw new DomainError(409,
      "The laptop must be actively sharing a selected screen");
    s.active = true;
    s.code = null;
    const now = this.now();
    s.expiresAt = now + CONTROL_TTL;
    s.lastPoll = now;
    return this.status();
  }
  activateTrusted() {
    const s = this.current();
    if (!s?.trusted) throw new DomainError(409,
      "One-tap control is not locally enabled. Enable trusted mobile control on the laptop once.");
    if (!this.captureFresh()) throw new DomainError(409,
      "Choose a screen on the laptop before starting phone control.");
    if (this.now() - s.lastPoll >= HEARTBEAT_TTL)
      throw new DomainError(409, "Windows control companion is no longer running.");
    if (s.active) return this.status();
    s.active = true;
    s.expiresAt = this.now() + CONTROL_TTL;
    s.lastAction = 0;
    s.queue = [];
    return this.status();
  }
  next(workerId, lastAck = null) {
    const s = this.current();
    if (!s || s.workerId !== workerId)
      throw new DomainError(409, "Remote input is not enabled for this Windows helper");
    s.lastPoll = this.now();
    if (s.trusted && !s.active) s.expiresAt = this.now() + TRUSTED_IDLE_TTL;
    if (s.trusted && s.active && !this.captureFresh()) {
      this.pause(s); // A stale/missing picture cannot authorize hidden input.
      s.expiresAt = this.now() + TRUSTED_IDLE_TTL;
    }
    // The visible helper piggybacks the previous result on its next poll.
    // Never store raw key/text contents in the acknowledgment.
    if (lastAck && s.active && s.dispatched &&
        lastAck.id === s.dispatched.id &&
        typeof lastAck.ok === "boolean") {
      s.lastResult = {
        id: s.dispatched.id, type: s.dispatched.type, ok:lastAck.ok,
        at: new Date(this.now()).toISOString(),
      };
      s.dispatched = null;
    }
    if (!s.active || !this.captureFresh())
      return { action: null, ...this.status() };
    const action = s.queue.shift() ?? null;
    if (action) s.dispatched = {id:action.id,type:action.type};
    return { action, ...this.status() };
  }
  action(input) {
    const s = this.current();
    if (!s?.active || !this.captureFresh())
      throw new DomainError(409, "Remote input unavailable. Pair the visible Windows helper and share the screen");
    const now = this.now();
    if (now - s.lastPoll >= HEARTBEAT_TTL)
      throw new DomainError(409, "Windows input helper disconnected");
    const value = validateAction(input);
    if (value.type === "tap" && !this.captureDisplay())
      throw new DomainError(409,
        "Tap-to-click requires a full-display share. Use the relative trackpad for windows or tabs.");
    // The phone may generate many small trackpad movements before the visible
    // Windows helper polls. Merge ONLY adjacent movements: never skip a click,
    // key or text action between moves, and never reorder inputs.
    if (value.type === "move" && s.queue.at(-1)?.type === "move") {
      const previous = s.queue.at(-1);
      const x = previous.dx + value.dx, y = previous.dy + value.dy;
      if (Math.abs(x) <= 150 && Math.abs(y) <= 150) {
        previous.dx = x; previous.dy = y;
        return { accepted: true, coalesced: true, queueDepth:s.queue.length,
          actionId:previous.id };
      }
    }
    if (now - s.lastAction < MIN_GAP && value.type !== "move")
      throw new DomainError(429, "Remote input rate limit");
    if (s.queue.length >= MAX_QUEUE)
      throw new DomainError(429, "Windows input queue full");
    value.id = ++s.nextId;
    s.queue.push(value);
    s.lastAction = now;
    return { accepted: true, queueDepth:s.queue.length, actionId:value.id };
  }
  stop(workerId = null) {
    const s = this.current();
    if (workerId != null && s && s.workerId !== workerId)
      throw new DomainError(403, "Incorrect Windows helper");
    if (workerId == null && s?.trusted) {
      // Mobile Stop revokes input but leaves the locally visible, opted-in
      // helper online; the owner must explicitly press Control to re-arm.
      this.pause(s);
      s.expiresAt = this.now() + TRUSTED_IDLE_TTL;
    } else {
      // Closing the local helper or revoking legacy pairing destroys consent.
      this.session = null;
    }
    return this.status();
  }
}
