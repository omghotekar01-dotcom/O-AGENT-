"use strict";
const fs = require("node:fs/promises");
const nodePath = require("node:path");
const { createHash } = require("node:crypto");
const { safeRelativePath, withinWorkspace } = require("./path-policy.cjs");

const MAX_TEXT = 48000;
const BLOCKED_NAMES = new Set([
  ".git", ".env", ".ssh", ".aws", ".npmrc", ".pypirc", ".netrc",
  "node_modules", ".venv", "__pycache__", ".terraform",
  "id_rsa", "id_ed25519", "credentials", "secrets.json",
]);
const BLOCKED_SUFFIXES = [".pem", ".p12", ".pfx", ".key", ".keystore",
  ".db", ".sqlite", ".sqlite3", ".png", ".jpg", ".jpeg", ".webp",
  ".gif", ".pdf", ".zip", ".exe", ".dll", ".vsix"];
const hash = content => createHash("sha256").update(content, "utf8").digest("hex");
function allowedPath(relative) {
  if (relative === "") return true;
  if (!safeRelativePath(relative)) return false;
  return relative.split(/[\\/]/).every((part) => {
    const lower = part.toLowerCase();
    return !lower.startsWith(".") && !BLOCKED_NAMES.has(lower) &&
      !BLOCKED_SUFFIXES.some(ext => lower.endsWith(ext));
  });
}
async function locate(root, relative, kind = "file") {
  if (!allowedPath(relative)) throw Error("Protected or invalid workspace-relative path");
  const target = nodePath.resolve(root, relative || ".");
  const real = await fs.realpath(target);
  if (!withinWorkspace(root, real)) throw Error("Path resolves outside enrolled VS Code workspace");
  const meta = await fs.lstat(target);
  if (meta.isSymbolicLink()) throw Error("Symbolic links are not accessible");
  if (kind === "dir" && !meta.isDirectory()) throw Error("Folder no longer exists");
  if (kind === "file" && !meta.isFile()) throw Error("File no longer exists");
  return {path:real,meta};
}
async function listWorkspaceFolder(root, relative = "") {
  const {path} = await locate(root,relative,"dir");
  const names = await fs.readdir(path,{withFileTypes:true});
  const entries = names.filter(e=>allowedPath(
    [relative,e.name].filter(Boolean).join("/")) &&
    (e.isFile() || e.isDirectory())).sort((a,b)=>
      Number(b.isDirectory()) - Number(a.isDirectory()) ||
      a.name.localeCompare(b.name));
  const result = [];
  for (const entry of entries.slice(0,150)) {
    const child = [relative,entry.name].filter(Boolean).join("/");
    result.push({ name:entry.name, path:child,
      type:entry.isDirectory()?"directory":"file" });
  }
  return {root,folder:relative,entries:result,
    truncated:entries.length>150};
}
async function readWorkspaceText(root,relative,vscode) {
  const {path,meta} = await locate(root,relative);
  if(meta.size > MAX_TEXT * 4) throw Error("File too large for mobile text editor");
  const doc = await vscode.workspace.openTextDocument(vscode.Uri.file(path));
  const content = doc.getText();
  if (content.length > MAX_TEXT || content.includes("\0") ||
      content.includes("\uFFFD"))
    throw Error("File is too large or not supported as UTF-8 text");
  return {path:relative,content,hash:hash(content),dirty:doc.isDirty,
    readOnly:doc.isDirty, language:doc.languageId};
}
async function writeWorkspaceText(root,relative,content,expectedHash,vscode) {
  if (!allowedPath(relative) || relative === "")
    throw Error("Protected file path");
  if (typeof content !== "string" || content.length > MAX_TEXT || content.includes("\0"))
    throw Error("Only text files up to 48,000 characters can be edited");
  if (typeof expectedHash !== "string" || !/^[a-f0-9]{64}$/.test(expectedHash))
    throw Error("Invalid original file version");
  const {path,meta} = await locate(root,relative);
  if (meta.size > MAX_TEXT * 4) throw Error("File too large to edit");
  const doc = await vscode.workspace.openTextDocument(vscode.Uri.file(path));
  if (doc.isDirty) throw Error("File has unsaved local edits. Save or discard them in VS Code before remote editing.");
  if (hash(doc.getText()) !== expectedHash)
    throw Error("File changed since it was loaded on your phone. Refresh before saving.");
  const edit = new vscode.WorkspaceEdit();
  const end = doc.positionAt(doc.getText().length);
  edit.replace(doc.uri,new vscode.Range(new vscode.Position(0,0),end),content);
  if (!await vscode.workspace.applyEdit(edit))
    throw Error("VS Code rejected the requested edit");
  if (!await doc.save()) throw Error("VS Code could not save changes to disk");
  return {path:relative,hash:hash(content),saved:true};
}
module.exports={allowedPath,listWorkspaceFolder,readWorkspaceText,writeWorkspaceText,hash,MAX_TEXT};
