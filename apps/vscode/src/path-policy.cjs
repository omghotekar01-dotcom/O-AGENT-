const { resolve, relative, isAbsolute, sep } = require("node:path");
function safeRelativePath(input) {
  return typeof input === "string" && input.length > 0 && input.length <= 350 &&
    !isAbsolute(input) && !/^[A-Za-z]:/.test(input) &&
    !/[\x00-\x1f]/.test(input) &&
    input.split(/[\\/]/).every(s => !!s && s !== "." && s !== "..");
}
function withinWorkspace(root, target) {
  const rel = relative(resolve(root), resolve(target));
  return !rel.startsWith(".." + sep) && rel !== ".." &&
    !isAbsolute(rel);
}
module.exports = {safeRelativePath,withinWorkspace};
