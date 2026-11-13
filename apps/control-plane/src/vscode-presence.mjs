import { DomainError } from "./core.mjs";

const MAX_ENTRIES = 100;
const STALE_AFTER_MS = 20000;
/** Ephemeral source-control presence from a visibly enrolled VS Code window.
 * Never transfers file contents, credentials, editor chat or terminal output.
 */
export class VscodePresence {
  constructor({ now = () => Date.now() } = {}) {
    this.now = now;
    this.snapshots = new Map();
  }
  publish(workerId, value) {
    if (typeof workerId !== "string" || !/^[a-zA-Z0-9_-]{1,100}$/.test(workerId))
      throw new DomainError(400, "Invalid enrolled editor");
    if (!value || typeof value !== "object" || Array.isArray(value))
      throw new DomainError(400, "Invalid workspace update");
    const workspace = value.workspace;
    if (typeof workspace !== "string" || workspace.length < 3 || workspace.length > 600)
      throw new DomainError(400, "Invalid workspace folder");
    if (!Array.isArray(value.changed) || value.changed.length > MAX_ENTRIES)
      throw new DomainError(400, "Invalid changed file list");
    const changed = value.changed.map(item => {
      if (!item || typeof item !== "object" || Array.isArray(item) ||
          typeof item.path !== "string" || item.path.length < 1 || item.path.length > 300 ||
          /[\u0000-\u001f]/.test(item.path) ||
          typeof item.status !== "string" || item.status.length > 32 ||
          !/^(modified|added|deleted|renamed|untracked|conflicted|unsaved)$/.test(item.status))
        throw new DomainError(400, "Invalid changed file entry");
      return { path: item.path, status: item.status };
    });
    this.snapshots.set(workerId, {
      workerId, workspace, changed, trackedAt: new Date(this.now()).toISOString(),
      touchedAt: this.now(), source: "vscode_local_extension",
    });
    return { accepted: true, changedCount: changed.length };
  }
  list() {
    const now = this.now();
    const items = [];
    for (const [id, entry] of this.snapshots) {
      if (now - entry.touchedAt > STALE_AFTER_MS) {
        this.snapshots.delete(id);
      } else {
        const { touchedAt, ...safe } = entry;
        items.push(safe);
      }
    }
    return { items, retention: "in_memory_only", staleAfterMs: STALE_AFTER_MS };
  }
  clear(workerId) {
    this.snapshots.delete(workerId);
    return { accepted: true };
  }
}
