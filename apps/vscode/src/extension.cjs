"use strict";
const vscode = require("vscode");
const { hostname } = require("node:os");
const { execFile } = require("node:child_process");
const { promisify } = require("node:util");
const execFileAsync = promisify(execFile);
const { realpath, stat, readdir } = require("node:fs/promises");
const { resolve, basename } = require("node:path");
const { safeRelativePath, withinWorkspace } = require("./path-policy.cjs");

const STORAGE_URL = "oagent.server";
const STORAGE_TOKEN = "oagent.workerToken";
let running = false, timer = null, pending = false, statusBar = null;
let contextRef = null;
const workerId = "vscode-" + hostname().replace(/[^a-zA-Z0-9_-]/g,"").slice(0,32) + "-companion";
const caps = ["workspace_inventory","vscode_open_file"];
async function settings() {
  const origin = await contextRef.secrets.get(STORAGE_URL);
  const token = await contextRef.secrets.get(STORAGE_TOKEN);
  if (!origin || !token) throw Error("Configure secure companion first");
  const url = new URL(origin);
  if (url.protocol !== "https:" ||
      url.username || url.password || url.search || url.hash ||
      (url.pathname !== "/" && url.pathname !== "")) {
    throw Error("A trusted HTTPS backend origin is required");
  }
  if (token.length < 24) throw Error("Invalid enrolled worker token");
  return {url,token};
}
async function api(path, body, method = "POST") {
  const {url,token} = await settings();
  const result = await fetch(new URL(path,url),{
    method,headers:{"Authorization":"Bearer " + token,"Content-Type":"application/json"},
    ...(method !== "GET" ? {body:JSON.stringify(body||{})} : {}),
    signal:AbortSignal.timeout(15000),redirect:"error",
  });
  const json = await result.json().catch(()=>({}));
  if (!result.ok) throw Error("Backend returned HTTP " + result.status);
  return json;
}
async function currentWorkspace() {
  const root = vscode.workspace.workspaceFolders?.[0]?.uri?.fsPath;
  if (!root) throw Error("Open and trust a workspace folder in VS Code first");
  if (!vscode.workspace.isTrusted) throw Error("VS Code workspace trust is required");
  return realpath(root);
}
async function inventory() {
  const root = await currentWorkspace();
  const names = (await readdir(root)).slice(0,75);
  const entries = [];
  for (const name of names) {
    const f = resolve(root,name);
    const s = await stat(f).catch(()=>null);
    if (s) entries.push({name:basename(name),type:s.isDirectory()?"directory":s.isFile()?"file":"other"});
  }
  return {workspace:root,entries,source:"vscode_extension",capturedAt:new Date().toISOString()};
}
/** Only filenames and changed/dirty statuses are transmitted; never file text,
 * diffs, VS Code chat, tabs, editor selections or authentication material.
 */
async function changedFiles() {
  const root = await currentWorkspace();
  const entries = new Map();
  try {
    const {stdout} = await execFileAsync("git",
      ["-C", root, "status", "--porcelain=v1", "--untracked-files=normal"],
      {timeout: 4500, maxBuffer: 30000, windowsHide: true});
    for (const line of stdout.split(/\\r?\\n/).slice(0, 110)) {
      if (line.length < 4) continue;
      const code = line.slice(0, 2);
      const file = line.slice(3).trim().slice(0, 300);
      if (!file || file.includes("\\0") || /[\\r\\n]/.test(file)) continue;
      const status = code === "??" ? "untracked" :
        code.includes("U") ? "conflicted" :
        code.includes("D") ? "deleted" :
        code.includes("R") ? "renamed" :
        code.includes("A") ? "added" : "modified";
      entries.set(file, status);
    }
  } catch {
    // Git isn't installed, repo has no Git root or status timed out.
    // Dirty VS Code documents can still be reported independently.
  }
  for (const doc of vscode.workspace.textDocuments) {
    if (!doc.isDirty || doc.uri.scheme !== "file" ||
        !withinWorkspace(root, doc.uri.fsPath)) continue;
    const relative = require("node:path").relative(root, doc.uri.fsPath);
    if (relative && !relative.startsWith("..") && entries.size < 100)
      entries.set(relative.slice(0, 300), "unsaved");
  }
  return {workspace: root,
    changed: [...entries.entries()].slice(0, 100).map(([path, status]) =>
      ({path, status}))};
}

async function publishChangedFiles() {
  const snapshot = await changedFiles();
  await api("/api/workers/" + workerId + "/vscode/snapshot", snapshot);
}

async function openFile(task) {
  const root = await currentWorkspace();
  const relative = task.parameters?.relativePath;
  if (!safeRelativePath(relative)) throw Error("Invalid relative file path");
  const dest = resolve(root,relative);
  const real = await realpath(dest);
  if (!withinWorkspace(root,real)) throw Error("File resolves outside trusted workspace");
  const s = await stat(real);
  if (!s.isFile()) throw Error("Target must be a file");
  const decision = await vscode.window.showWarningMessage(
    "O-AGENT owner requests opening this file in your VS Code workspace: " +
      relative + ". This action will not send file contents to the phone.",
    {modal:true}, "Open file", "Deny");
  if (decision !== "Open file") return {opened:false,reason:"Local VS Code user denied"};
  const document = await vscode.workspace.openTextDocument(vscode.Uri.file(real));
  await vscode.window.showTextDocument(document,{preview:true,preserveFocus:false});
  return {opened:true,relativePath:relative};
}
async function runTask(task) {
  if (!task || task.workerId !== workerId || !caps.includes(task.kind))
    throw Error("Invalid task for this extension");
  if (task.kind === "workspace_inventory") return inventory();
  if (task.kind === "vscode_open_file") return openFile(task);
  throw Error("Unsupported VS Code action");
}
async function poll() {
  if (!running || pending) return;
  pending = true;
  try {
    await api("/api/workers/" + workerId + "/heartbeat");
    await publishChangedFiles();
    const {task} = await api("/api/workers/" + workerId + "/next");
    if (task) {
      try {
        const result = await runTask(task);
        await api("/api/workers/" + workerId + "/tasks/" + task.id + "/finish",
          {ok:true,result});
      } catch {
        await api("/api/workers/" + workerId + "/tasks/" + task.id + "/finish",
          {ok:false,error:"VS Code operation denied or unavailable"}).catch(()=>{});
      }
    }
    statusBar.text = "$(shield) O-AGENT: connected";
    statusBar.tooltip = "Explicitly enrolled VS Code companion; no background screen capture.";
  } catch {
    statusBar.text = "$(warning) O-AGENT: disconnected";
  } finally { pending = false; }
}
async function stop() {
  if (running) {
    try { await api("/api/workers/" + workerId + "/vscode/snapshot", {}, "DELETE"); }
    catch { /* server expires data independently */ }
  }
  running = false;
  if (timer) clearInterval(timer);
  timer = null;
  if (statusBar) {statusBar.text="$(circle-slash) O-AGENT: stopped";statusBar.tooltip="No VS Code workspace polling"; }
}
async function start() {
  if (running) return;
  if (!vscode.workspace.isTrusted) {
    vscode.window.showWarningMessage("Trust this VS Code workspace before enabling remote control.");
    return;
  }
  try {
    await settings();
    const confirm = await vscode.window.showInformationMessage(
      "Enroll this VS Code workspace? O-AGENT may send a short list of changed "
      + "and unsaved file names (NEVER file contents) to your private owner backend "
      + "while this companion is enabled. Opening a file still requires approval "
      + "on the phone and in this IDE. No edits or Copilot chats are transmitted.",
      {modal:true}, "Enable", "Cancel");
    if (confirm !== "Enable") return;
    await api("/api/workers/register",{id:workerId,name:"VS Code " + hostname(),capabilities:caps});
    running = true;
    statusBar.show();
    await poll();
    timer = setInterval(() => { void poll(); }, 5000);
  } catch {
    vscode.window.showErrorMessage("O-AGENT connection failed. Check HTTPS URL and worker enrollment token.");
  }
}
async function configure() {
  const url = await vscode.window.showInputBox({
    title:"O-AGENT backend HTTPS URL",
    prompt:"Enter the exact private HTTPS origin; no URL path or credentials",
    ignoreFocusOut:true,validateInput:v=> {
      try {const u=new URL(v);return u.protocol==="https:"&&!!u.host&&u.pathname==="/"?"": "Enter only a trusted HTTPS origin";}
      catch{return "Invalid URL"}
    },
  });
  if (!url) return;
  const secret = await vscode.window.showInputBox({
    title:"Enrolled worker token",prompt:"Paste your own O-AGENT worker token",
    password:true,ignoreFocusOut:true,
    validateInput:v=>v.length>=24?"":"At least 24 characters required",
  });
  if (!secret) return;
  await contextRef.secrets.store(STORAGE_URL,url);
  await contextRef.secrets.store(STORAGE_TOKEN,secret);
  vscode.window.showInformationMessage("O-AGENT credentials stored in VS Code SecretStorage. Choose Start to opt in.");
}
function activate(context) {
  contextRef = context;
  statusBar = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right,90);
  statusBar.text="$(circle-slash) O-AGENT: stopped";
  statusBar.command="oagent.start";
  statusBar.show();
  context.subscriptions.push(statusBar,
    vscode.commands.registerCommand("oagent.configure",configure),
    vscode.commands.registerCommand("oagent.start",start),
    vscode.commands.registerCommand("oagent.stop",stop));
}
function deactivate() { void stop(); }
module.exports={activate,deactivate};
