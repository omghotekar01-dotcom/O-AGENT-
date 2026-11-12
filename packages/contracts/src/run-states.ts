/** Server-authoritative lifecycle for OMIO task runs. */
export type RunState =
  | "draft"
  | "ready"
  | "queued"
  | "starting"
  | "running"
  | "waiting_for_input"
  | "waiting_for_approval"
  | "waiting_for_device"
  | "paused"
  | "recovering"
  | "completed"
  | "failed"
  | "cancelled";

export const TERMINAL_RUN_STATES: ReadonlySet<RunState> = new Set([
  "completed",
  "failed",
  "cancelled",
]);

const ALLOWED_TRANSITIONS: Readonly<Record<RunState, readonly RunState[]>> = {
  draft: ["ready", "cancelled"],
  ready: ["queued", "cancelled"],
  queued: ["starting", "cancelled", "failed"],
  starting: ["running", "waiting_for_device", "recovering", "failed", "cancelled"],
  running: [
    "waiting_for_input",
    "waiting_for_approval",
    "waiting_for_device",
    "paused",
    "recovering",
    "completed",
    "failed",
    "cancelled",
  ],
  waiting_for_input: ["running", "paused", "cancelled", "failed"],
  waiting_for_approval: ["running", "paused", "cancelled", "failed"],
  waiting_for_device: ["starting", "paused", "cancelled", "failed"],
  paused: ["queued", "starting", "running", "cancelled"],
  recovering: ["starting", "running", "waiting_for_device", "failed", "cancelled"],
  completed: [],
  failed: [],
  cancelled: [],
};

export function isAllowedRunTransition(from: RunState, to: RunState): boolean {
  return ALLOWED_TRANSITIONS[from].includes(to);
}

export function isTerminalRunState(state: RunState): boolean {
  return TERMINAL_RUN_STATES.has(state);
}
