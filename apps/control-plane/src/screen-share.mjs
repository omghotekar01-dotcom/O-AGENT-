import { randomBytes, timingSafeEqual } from "node:crypto";
import { DomainError } from "./core.mjs";

const MAX_FRAME_BYTES = 160000;
const FRAME_TTL_MS = 4000;
const LEASE_TTL_MS = 30 * 60 * 1000;
const FRAME_GAP_MS = 550;

/**
 * Owner-only, consent-driven, ephemeral JPEG screen previews. A human on
 * the laptop must click the native getDisplayMedia picker. No OS capture
 * hooks, automation, background screenshots, disk storage or remote input.
 */
export class ScreenShare {
  constructor({ now = () => Date.now() } = {}) {
    this.now = now;
    this.active = null;
  }
  status() {
    const s = this.active;
    if (!s) return { supported: true, capturing: false, fresh: false };
    if (this.now() > s.expiresAt) {
      this.active = null;
      return { supported: true, capturing: false, fresh: false };
    }
    return {
      supported: true, capturing: true,
      fresh: !!s.frame && this.now() - s.lastFrameAt < FRAME_TTL_MS,
      startedAt: new Date(s.startedAt).toISOString(),
      lastFrameAt: s.lastFrameAt ? new Date(s.lastFrameAt).toISOString() : null,
      expiresAt: new Date(s.expiresAt).toISOString(),
      frameSequence: s.sequence,
      mode: "view_only_consent_screen_frames",
    };
  }
  start() {
    this.status(); // prune expired streams
    if (this.active) throw new DomainError(409,
      "A screen-sharing session is already active. Stop it before starting another.");
    const token = randomBytes(32).toString("base64url");
    const now = this.now();
    this.active = {
      token, startedAt: now, expiresAt: now + LEASE_TTL_MS,
      lastFrameAt: 0, frame: null, sequence: 0,
    };
    return { captureToken: token, ...this.status() };
  }
  stop() {
    this.active = null;
    return { supported: true, capturing: false, fresh: false };
  }
  frame() {
    const status = this.status();
    if (!status.capturing || !status.fresh)
      throw new DomainError(404, "No fresh, consented screen frame available");
    return { bytes: this.active.frame, sequence: this.active.sequence };
  }
  publish(token, bytes) {
    const status = this.status();
    if (!status.capturing) throw new DomainError(409, "No active screen capture");
    if (typeof token !== "string" || token.length !== this.active.token.length ||
        !timingSafeEqual(Buffer.from(token), Buffer.from(this.active.token)))
      throw new DomainError(403, "Invalid capture-session token");
    if (!Buffer.isBuffer(bytes) || bytes.length < 60 ||
        bytes.length > MAX_FRAME_BYTES ||
        bytes[0] !== 0xff || bytes[1] !== 0xd8 ||
        bytes.at(-2) !== 0xff || bytes.at(-1) !== 0xd9)
      throw new DomainError(400, "Expected a bounded JPEG image");
    const now = this.now();
    if (now - this.active.lastFrameAt < FRAME_GAP_MS)
      throw new DomainError(429, "Frame rate capped at one image per 550 ms");
    this.active.frame = Buffer.from(bytes);
    this.active.lastFrameAt = now;
    this.active.sequence += 1;
    return { accepted: true, frameSequence: this.active.sequence };
  }
  static get maxFrameBytes() { return MAX_FRAME_BYTES; }
}
