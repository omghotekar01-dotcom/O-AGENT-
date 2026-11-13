/**
 * Child Codex processes inherit only OS and Codex home settings needed for
 * CLI login. Never forward O-AGENT owner/worker/vault, other AI API keys,
 * GitHub credentials or arbitrary user environment secrets.
 */
const ALLOWED = new Set([
  "PATH","HOME","USERPROFILE","APPDATA","LOCALAPPDATA","PROGRAMDATA",
  "SYSTEMROOT","WINDIR","COMSPEC","PATHEXT","TEMP","TMP","TMPDIR",
  "LANG","LC_ALL","LC_CTYPE","TERM","TZ","XDG_CONFIG_HOME",
  "XDG_CACHE_HOME","XDG_DATA_HOME","USER","USERNAME","HOMEDRIVE",
  "HOMEPATH","OS","SYSTEMDRIVE","NUMBER_OF_PROCESSORS",
  "PROCESSOR_ARCHITECTURE","SHELL","CODEX_HOME",
]);
export function codexChildEnv(env = process.env) {
  return Object.fromEntries(Object.entries(env).filter(([k,v]) =>
    ALLOWED.has(k.toUpperCase()) && typeof v === "string"));
}
