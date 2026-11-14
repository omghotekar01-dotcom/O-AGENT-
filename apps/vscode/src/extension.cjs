"use strict";
const vscode = require("vscode");
const { hostname } = require("node:os");
const { execFile } = require("node:child_process");
const { promisify } = require("node:util");
const execFileAsync = promisify(execFile);
const { realpath, stat, readdir } = require("node:fs/promises");
const { resolve, basename } = require("node:path");
const { safeRelativePath, withinWorkspace } = require("./path-policy.cjs");
const { parseBackendOrigin, explainHttpFailure, explainFetchFailure } = require("./connection.cjs");
const { readLocalEnrollment, verifyLocalBackend } = require("./local-enrollment.cjs");
const { listWorkspaceFolder, readWorkspaceText, writeWorkspaceText,
  createWorkspaceText,renameWorkspaceFile,deleteWorkspaceFile } = require("./file-access.cjs");

const STORAGE_URL = "oagent.server";
const STORAGE_TOKEN = "oagent.workerToken";
let running = false, timer = null, pending = false, statusBar = null;
let mobileEditsUntil = 0;
let enrolledRoot = null;
let contextRef = null;
let treeViewEmitter = null; 
const updateTree = () => { if (treeViewEmitter) treeViewEmitter.fire(); };
const workerId = "vscode-" + hostname().replace(/[^a-zA-Z0-9_-]/g,"").slice(0,32) + "-companion";
const caps = ["workspace_inventory","vscode_open_file","vscode_workspace_files"];
async function settings() {
  const origin = await contextRef.secrets.get(STORAGE_URL);
  const token = await contextRef.secrets.get(STORAGE_TOKEN);
  if (!origin || !token) throw Error("Configure secure companion first");
  const url = parseBackendOrigin(origin);
  if (token.length < 24) throw Error("Invalid enrolled worker token");
  return {url,token};
}
async function api(path, body, method = "POST") {
  const {url,token} = await settings();
  let result;
  try {
    result = await fetch(new URL(path,url),{
      method,headers:{"Authorization":"Bearer " + token,"Content-Type":"application/json"},
      ...(method !== "GET" ? {body:JSON.stringify(body||{})} : {}),
      signal:AbortSignal.timeout(15000),redirect:"error",
    });
  } catch (error) {
    throw Error(explainFetchFailure(error, url));
  }
  const json = await result.json().catch(()=>({}));
  if (!result.ok) throw Error(explainHttpFailure(result.status, path));
  return json;
}
async function checkBackend() {
  const { url } = await settings();
  let response;
  // Verify the configured service before sending the worker token anywhere.
  try {
    response = await fetch(new URL("/health", url), {
      method: "GET", signal: AbortSignal.timeout(7000),
      cache: "no-store", redirect: "error",
    });
  } catch (error) {
    throw Error(explainFetchFailure(error, url));
  }
  if (!response.ok) throw Error(
    "O-AGENT health check failed (HTTP " + response.status + "). Check the backend address.");
  const data = await response.json().catch(() => ({}));
  if (data?.service !== "oagent-control-plane" || data?.status !== "ok")
    throw Error("The configured address is not the O-AGENT backend. Use http://127.0.0.1:8787 on the laptop.");
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
    for (const line of stdout.split(/\r?\n/).slice(0, 110)) {
      if (line.length < 4) continue;
      const code = line.slice(0, 2);
      const file = line.slice(3).trim().slice(0, 300);
      if (!file || file.includes("\0") || /[\r\n]/.test(file)) continue;
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
  let real;
  try { real = await realpath(dest); }
  catch { throw Error("File does not exist under the enrolled VS Code folder. Use Browse project files to pick an existing path."); }
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
async function processMobileFiles() {
  const {request} = await api("/api/workers/" + workerId + "/vscode/files/next",{});
  if (!request) return;
  try {
    const root = await currentWorkspace();
    let result;
    if (request.op === "list") {
      result = await listWorkspaceFolder(root,request.path);
    } else if (request.op === "read") {
      result = await readWorkspaceText(root,request.path,vscode);
    } else if (["write","create","rename","delete"].includes(request.op)) {
      if (Date.now() > mobileEditsUntil)
        throw Error("Mobile file modifications are disabled. Enable them locally in VS Code for 30 minutes.");
      if (request.op === "write") {
        result = await writeWorkspaceText(root,request.path,
          request.content,request.expectedHash,vscode);
      } else if (request.op === "create") {
        result = await createWorkspaceText(root,request.path,request.content,vscode);
      } else if (request.op === "rename") {
        result = await renameWorkspaceFile(root,request.path,
          request.newPath,request.expectedHash,vscode);
      } else {
        result = await deleteWorkspaceFile(root,request.path,request.expectedHash,vscode);
      }
    } else {
      throw Error("Unsupported file operation");
    }
    await api("/api/workers/" + workerId + "/vscode/files/finish",
      {id:request.id,ok:true,result});
  } catch (error) {
    // The result is only sent to the authenticated OWNER, and never persisted.
    const message = error instanceof Error ? error.message : "Workspace file operation failed";
    await api("/api/workers/" + workerId + "/vscode/files/finish",
      {id:request.id,ok:false,error:message.slice(0,250)}).catch(()=>{});
  }
}
async function poll() {
  if (!running || pending) return;
  pending = true;
  try {
    const actualRoot = await currentWorkspace();
    if (!enrolledRoot || actualRoot !== enrolledRoot) {
      await stop();
      vscode.window.showWarningMessage("VS Code project folder changed. Start O-AGENT again to consent to the new workspace.");
      return;
    }
    await api("/api/workers/" + workerId + "/heartbeat");
    await publishChangedFiles();
    await processMobileFiles();
    const {task} = await api("/api/workers/" + workerId + "/next");
    if (task) {
      try {
        const result = await runTask(task);
        await api("/api/workers/" + workerId + "/tasks/" + task.id + "/finish",
          {ok:true,result});
      } catch (error) {
        const message = error instanceof Error ? error.message : "VS Code operation unavailable";
        const safe = /File does not exist|Invalid|denied|not a file|workspace/i.test(message)
          ? message.slice(0,240)
          : "VS Code operation unavailable. Open the exact project folder and retry.";
        await api("/api/workers/" + workerId + "/tasks/" + task.id + "/finish",
          {ok:false,error:safe}).catch(()=>{});
      }
    }
    statusBar.text = "$(shield) O-AGENT: connected";
    statusBar.tooltip = "Connected: " + enrolledRoot + ". Open the O-AGENT sidebar to manage permissions.";
    updateTree();
  } catch (error) {
    statusBar.text = "$(warning) O-AGENT: disconnected";
    statusBar.tooltip = error.message;
    updateTree();
  } finally { pending = false; }
}
async function stop() {
  mobileEditsUntil = 0;
  enrolledRoot = null;
  if (running) {
    try { await api("/api/workers/" + workerId + "/vscode/files/stop",{}); }
    catch { /* ephemeral relay expires independently */ }
    try { await api("/api/workers/" + workerId + "/vscode/snapshot", {}, "DELETE"); }
    catch { /* server expires data independently */ }
  }
  running = false;
  if (timer) clearInterval(timer);
  timer = null;
  if (statusBar) {statusBar.text="$(circle-slash) O-AGENT: stopped";statusBar.tooltip="No VS Code workspace polling"; }
  updateTree();
}
async function start() {
  if (running) return;
  if (!vscode.workspace.isTrusted) {
    vscode.window.showWarningMessage("Trust this VS Code workspace before enabling remote control.");
    return;
  }
  try {
    await settings();
    await checkBackend();
    const root = await currentWorkspace();
    const confirm = await vscode.window.showInformationMessage(
      "Enroll this exact VS Code folder: " + root + "? "
      + "Enable O-AGENT for this trusted workspace? The owner phone may list folders "
      + "and view non-secret text files within this project. Contents are relayed "
      + "temporarily and never stored in the backend database. Changes require "
      + "a separate locally enabled 30-minute editing window AND confirmation on "
      + "the phone. Copilot chats, secrets and external folders are not accessible.",
      {modal:true}, "Enable", "Cancel");
    if (confirm !== "Enable") return;
    await api("/api/workers/register",{id:workerId,name:"VS Code " + hostname(),capabilities:caps});
    enrolledRoot = root;
    running = true;
    statusBar.show();
    updateTree();
    await poll();
    timer = setInterval(() => { void poll(); }, 5000);
  } catch (error) {
    const detail = error instanceof Error ? error.message : "Unknown connection error";
    statusBar.text = "$(warning) O-AGENT: disconnected";
    statusBar.tooltip = detail;
    vscode.window.showErrorMessage("O-AGENT connection failed: " + detail);
    updateTree();
  }
}
async function enableMobileEdits() {
  if (!running) {
    vscode.window.showWarningMessage("Start the O-AGENT workspace companion first.");
    return;
  }
  const decision = await vscode.window.showWarningMessage(
    "Allow your O-AGENT owner phone to create, rename, move to Trash, or edit "
    + "allowed text files in this exact workspace for 30 minutes? Every action "
    + "requires confirmation on the phone. Rename/delete also check file versions; "
    + "Trash requests require an additional local approval. Stop the companion "
    + "at any time to revoke. Do not use with sensitive projects.",
    {modal:true},"Enable for 30 minutes","Cancel");
  if (decision !== "Enable for 30 minutes") return;
  mobileEditsUntil = Date.now()+30*60*1000;
  updateTree();
  vscode.window.showInformationMessage(
    "O-AGENT mobile file editing enabled for 30 minutes in this VS Code workspace.");
}
async function configure() {
  const url = await vscode.window.showInputBox({
    title:"O-AGENT backend URL",
    prompt:"Use http://127.0.0.1:8787 for VS Code on this laptop, or your trusted private HTTPS Tailscale origin.",
    value:"http://127.0.0.1:8787",
    ignoreFocusOut:true,validateInput:v=> {
      try { parseBackendOrigin(v); return ""; }
      catch (error) { return error.message; }
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
async function connectFromLaptop() {
  if (!vscode.workspace.isTrusted) {
    vscode.window.showWarningMessage("Open and trust the project folder in VS Code first.");
    return;
  }
  if (running) {
    vscode.window.showInformationMessage("O-AGENT is already connected to this workspace.");
    return;
  }
  const decision=await vscode.window.showInformationMessage(
    "Connect this VS Code window to the O-AGENT backend running on the same Windows laptop? "
    + "O-AGENT will read the WORKER token encrypted for your signed-in Windows account and "
    + "save it in VS Code SecretStorage. It will never display the secret or send it to "
    + "any third-party service. You must separately approve sharing this project folder.",
    {modal:true},"Connect this laptop","Cancel");
  if (decision!=="Connect this laptop") return;
  try {
    const {url,token}=await readLocalEnrollment({
      platform:process.platform,remoteName:vscode.env.remoteName,
    });
    // Check that the local socket is a real O-AGENT instance before storing
    // any token. Local credential import never sends it to remote URLs.
    await verifyLocalBackend(url);
    await contextRef.secrets.store(STORAGE_URL,url);
    await contextRef.secrets.store(STORAGE_TOKEN,token);
    vscode.window.showInformationMessage(
      "Local O-AGENT detected. Choose Enable to share this exact project folder.");
    await start();
  } catch(error) {
    vscode.window.showErrorMessage(
      "O-AGENT automatic connection failed: " + error.message +
      " You can still use Configure Secure Companion for a manual connection.");
  } finally { updateTree(); }
}
function treeItem(label,icon,command,description) {
  const item=new vscode.TreeItem(label,vscode.TreeItemCollapsibleState.None);
  item.iconPath=new vscode.ThemeIcon(icon);
  item.tooltip=description||label;
  if(command)item.command={command,title:label};
  return item;
}
const setupTree = {
  get onDidChangeTreeData() { return treeViewEmitter.event; },
  getTreeItem(element) { return element; },
  getChildren() {
    if (!running) return [
      treeItem("1 · Connect using Windows setup","plug","oagent.connectLocal",
        "Reads your current Windows-user O-AGENT worker credential once, with permission"),
      treeItem("Or connect manually","key","oagent.configure",
        "For a separate machine or trusted HTTPS backend"),
      treeItem("2 · Share current project","folder-opened","oagent.start",
        "Requires separate consent for the exact trusted workspace folder"),
    ];
    const editActive=Date.now()<mobileEditsUntil;
    return [
      treeItem("Connected · "+(enrolledRoot?basename(enrolledRoot):"Workspace"),"check",
        null,"Only this explicitly enrolled folder is visible"),
      treeItem(editActive ? "Editing enabled (temporary)" : "Allow edits for 30 minutes",
        editActive?"shield":"edit","oagent.enableMobileEdits",
        "Separate local permission for source editing; phone confirms each change"),
      treeItem("Stop sharing now","stop-circle","oagent.stop",
        "Immediately revokes the active workspace feed and editing window"),
    ];
  },
};
function activate(context) {
  contextRef = context;
  statusBar = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right,90);
  statusBar.text="$(circle-slash) O-AGENT: stopped";
  treeViewEmitter = new vscode.EventEmitter();
  statusBar.command="workbench.view.extension.oagentWorkspace";
  context.subscriptions.push(treeViewEmitter,
    vscode.window.registerTreeDataProvider("oagent.workspace",setupTree));
  statusBar.show();
  context.subscriptions.push(statusBar,
    vscode.commands.registerCommand("oagent.configure",configure),
    vscode.commands.registerCommand("oagent.connectLocal",connectFromLaptop),
    vscode.commands.registerCommand("oagent.start",start),
    vscode.commands.registerCommand("oagent.stop",stop),
    vscode.commands.registerCommand("oagent.enableMobileEdits",enableMobileEdits));
}
function deactivate() { void stop(); }
module.exports={activate,deactivate};
