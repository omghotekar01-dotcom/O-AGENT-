"use strict";
const $ = id => document.getElementById(id);
const create = (tag,text,cls) => {
  const node=document.createElement(tag);
  if(text!==undefined)node.textContent=String(text);
  if(cls)node.className=cls;
  return node;
};
const pad = target => target.replaceChildren(create("div","No activity to show yet.","empty"));
const safeStatus = value => String(value||"unknown").toLowerCase().replace(/[^a-z_]/g,"");
const escapePath = value => String(value||"").replace(/\\/g,"/");
const FOLDER_NAME=/^[a-zA-Z0-9][a-zA-Z0-9._-]{0,119}$/;
let token=sessionStorage.getItem("oagent_token")||"";
let connected=false,refreshing=false,currentView="overview";
let snapshot={workers:[],tasks:[]},workspaceFeed=[],projectFeed=[],integrations=[],events=[];
let activeFolder="",activeWorker="",openedFile=null,loadingFile=false;
let noticeTimer=null;
function notice(message,seconds=6){
  $("notice").textContent=String(message||"");
  if(noticeTimer)clearTimeout(noticeTimer);
  if(message)noticeTimer=setTimeout(()=>$("notice").textContent="",seconds*1000);
}
async function api(path,{method="GET",body,headers}={}){
  if(!token)throw Error("Connect your operator token first");
  const response=await fetch(path,{
    method,headers:{authorization:"Bearer "+token,accept:"application/json",
      ...(body!==undefined?{"content-type":"application/json"}:{}),...headers},
    ...(body!==undefined?{body:JSON.stringify(body)}:{}),
    cache:"no-store",redirect:"error",
  });
  const result=await response.json().catch(()=>({}));
  if(!response.ok)throw Error(result.error||("HTTP "+response.status));
  return result;
}
function badge(status){
  return create("span",String(status||"unknown").replaceAll("_"," "),"pill "+safeStatus(status));
}
function item(title,desc,state){
  const el=create("article",undefined,"item");
  const top=create("div",undefined,"item-head");
  top.append(create("strong",title));
  if(state)top.append(badge(state));
  el.append(top);
  if(desc)el.append(create("p",desc,"meta"));
  return el;
}
function action(container,label,fn,style="secondary"){
  const btn=create("button",label,"button "+style);
  btn.type="button";
  btn.addEventListener("click",async()=>{
    if(btn.disabled)return;
    btn.disabled=true;
    try{await fn();}catch(error){notice(error.message);}
    finally{btn.disabled=false;}
  });
  container.append(btn);
  return btn;
}
function navigate(view){
  if(currentView==="desktop" && view!=="desktop")desktopQueue.length=0;
  currentView=view;
  for(const section of document.querySelectorAll("[data-panel]"))section.hidden=section.dataset.panel!==view;
  for(const button of document.querySelectorAll(".nav-link")){
    const selected=button.dataset.view===view;
    button.classList.toggle("selected",selected);
    if(selected)button.setAttribute("aria-current","page");
    else button.removeAttribute("aria-current");
  }
  $("viewName").textContent=({
    overview:"Overview",files:"Project files",desktop:"Live desktop",
    activity:"Activity & approvals",
    integrations:"Connected tools",setup:"Guided setup",
  })[view]||"Workspace";
  $("sidebar").classList.remove("open");
  if(view==="files" && workspaceFeed.length && !activeWorker) {
    void chooseWorkspace(workspaceFeed[0].workerId);
  }
  if(view==="desktop" && connected) void desktopRefresh();
  window.scrollTo({top:0,behavior:"instant"});
}
function connectedUi(value){
  connected=value;
  $("authPanel").hidden=value;
  $("workspace").hidden=!value;
  $("disconnect").hidden=!value;
  $("connectionBadge").textContent=value?"Connected":"Not connected";
  $("connectionBadge").classList.toggle("connected",value);
  $("sideDot").classList.toggle("online",value);
  $("sideStatus").textContent=value?"Backend connected":"Not connected";
  if(!value) {
    desktopQueue.length=0;
    desktopState=null; desktopInput=null;
    clearDesktopPreview();
  }
}
function machinesView(){
  const workers=$("workerList");
  workers.replaceChildren();
  const select=$("workerSelect"), previous=select.value;
  select.replaceChildren();
  for(const worker of snapshot.workers||[]){
    const heartbeat=Number.isFinite(worker.lastSeenAt)?
      new Date(worker.lastSeenAt).toLocaleString():"Unknown";
    workers.append(item(worker.name||worker.id,
      (worker.id||"")+" · Last seen "+heartbeat,worker.status));
    if(worker.status==="online"){
      const opt=create("option",worker.name||worker.id);
      opt.value=worker.id;
      select.append(opt);
    }
  }
  if(!(snapshot.workers||[]).length)pad(workers);
  if(previous && [...select.options].some(o=>o.value===previous))select.value=previous;
  select.disabled=select.options.length===0;
  $("taskForm").querySelector("button[type=submit]").disabled=select.disabled;
  updateAvailableTaskKinds();
}
function updateAvailableTaskKinds(){
  const worker=(snapshot.workers||[]).find(w=>w.id===$("workerSelect").value);
  for(const option of $("kind").options)
    option.disabled=!worker?.capabilities?.includes(option.value);
  if($("kind").selectedOptions[0]?.disabled){
    const first=[...$("kind").options].find(o=>!o.disabled);
    if(first)$("kind").value=first.value;
  }
  $("taskForm").querySelector("button[type=submit]").disabled=
    !worker || ![...$("kind").options].some(o=>!o.disabled);
}
function taskView(){
  const panel=$("taskList");panel.replaceChildren();
  for(const task of (snapshot.tasks||[]).slice(0,40)){
    const el=item(task.kind?.replaceAll("_"," ")||"Task",
      (task.workerId||"")+" · "+new Date(task.createdAt).toLocaleString(),task.status);
    if(task.status==="waiting_for_approval"){
      const actions=create("div",undefined,"actions");
      action(actions,"Approve",async()=>{
        const confirm=await confirmAction("Approve this exact task?",
          "Operation: "+task.kind+"\nWorker: "+task.workerId+
          "\n\nApprove only if you trust the requested operation.");
        if(!confirm)return;
        await api("/api/tasks/"+encodeURIComponent(task.id)+"/decision",{
          method:"POST",body:{approve:true}});
        await refresh();
      },"primary");
      action(actions,"Reject",async()=>{
        await api("/api/tasks/"+encodeURIComponent(task.id)+"/decision",{
          method:"POST",body:{approve:false}});
        await refresh();
      });
      el.append(actions);
    }
    if(task.status==="queued"){
      const actions=create("div",undefined,"actions");
      action(actions,"Cancel",async()=>{
        await api("/api/tasks/"+encodeURIComponent(task.id)+"/cancel",{method:"POST"});
        await refresh();
      });
      el.append(actions);
    }
    if(task.error)el.append(create("p",task.error,"meta"));
    if(task.result && task.kind!=="codex_cli_history"){
      const details=create("details");
      details.append(create("summary","View result"),create("pre",JSON.stringify(task.result,null,2),"result"));
      el.append(details);
    }
    panel.append(el);
  }
  if(!snapshot.tasks?.length)pad(panel);
  const evPanel=$("eventList");evPanel.replaceChildren();
  for(const event of events.slice(-30).reverse()){
    evPanel.append(item(event.type||"Event",
      new Date(event.at).toLocaleString()+" · "+(event.taskId||event.workerId||""),null));
  }
  if(!events.length)pad(evPanel);
}
function projectView(){
  const root=$("projectList");
  root.replaceChildren();
  for(const project of projectFeed.slice(0,12)){
    const title=project.title||project.name||project.id||"Project";
    const status=project.status||project.connectionStatus||null;
    root.append(item(title,
      [project.source||project.provider||"Workspace",project.description||project.cwd||""].filter(Boolean).join(" · "),
      status));
  }
  if(!projectFeed.length)root.append(create("div",
    "No projects returned by your backend. Start a provider adapter or enroll a VS Code workspace.",
    "empty"));
}
function integrationView(){
  const root=$("integrationList");root.replaceChildren();
  for(const source of integrations){
    const el=create("article",undefined,"integration-card");
    const heading=create("div",undefined,"item-head");
    heading.append(create("h2",source.label||source.id||"Provider"),badge(source.status));
    el.append(heading);
    el.append(create("p",source.limitation||"Capabilities depend on your authenticated provider runtime."));
    const caps=Array.isArray(source.capabilities)?source.capabilities:[];
    if(caps.length){
      const label=create("p","Verified adapter capabilities","meta");el.append(label);
      const ul=create("ul");
      for(const c of caps.slice(0,9))ul.append(create("li",String(c).replaceAll("_"," ")));
      el.append(ul);
    } else el.append(create("p","No direct operations available from this connection.","meta"));
    root.append(el);
  }
  if(!integrations.length)root.append(create("div",
    "Provider status is unavailable. Check the backend and try Refresh.","empty"));
}
function workspacesView(){
  const select=$("workspaceSelect"),former=activeWorker||select.value;
  select.replaceChildren();
  for(const ws of workspaceFeed){
    const opt=create("option",ws.workspace||ws.workerId);
    opt.value=ws.workerId;
    select.append(opt);
  }
  if(former&&workspaceFeed.some(x=>x.workerId===former))select.value=former;
  $("openWorkspace").disabled=workspaceFeed.length===0;
  if(!workspaceFeed.length){
    $("fileList").replaceChildren(create("div",
      "No live VS Code workspace. Open a trusted project folder in VS Code and start the O-AGENT companion.","empty"));
    $("workspaceSelect").replaceChildren();
    clearFile();
  }
}
function updateGuidedSetup(){
  const online=(snapshot.workers||[]).filter(w=>w.status==="online").length;
  const folders=workspaceFeed.length;
  const usable=integrations.filter(s=>s.status==="connected").length;
  $("setupMachine").textContent=online ?
    online+" actual machine(s) online — ready." :
    "No machine is online. Run O-AGENT.cmd on the trusted laptop.";
  $("setupVsCode").textContent=folders ?
    folders+" live VS Code workspace(s) connected — open Project files to browse." :
    "No VS Code companion online. Use the O-AGENT sidebar in local VS Code to connect this folder.";
  $("setupFiles").textContent=folders ?
    "Browsing is available. Editing still requires the separate local 30-minute permission in VS Code." :
    "Connect a VS Code workspace first. Editing permission is always granted locally and temporarily.";
  $("setupProviders").textContent=usable ?
    usable+" provider adapter(s) verified. Check individual capabilities and usage quotas." :
    "No verified API provider connection. Other statuses may be configured but not tested.";
}
function syncUI(){
  updateGuidedSetup();
  $("machines").textContent=String(snapshot.workers?.length||0);
  $("online").textContent=String((snapshot.workers||[]).filter(w=>w.status==="online").length);
  $("running").textContent=String((snapshot.tasks||[]).filter(t=>t.status==="running").length);
  $("approvals").textContent=String((snapshot.tasks||[]).filter(t=>t.status==="waiting_for_approval").length);
  machinesView();taskView();projectView();integrationView();workspacesView();
}
async function refresh(){
  if(!token||refreshing||document.hidden)return;
  refreshing=true;
  try{
    const [state,ev,ws,providers,projects]=await Promise.all([
      api("/api/state"),api("/api/events"),
      api("/api/vscode/workspaces").catch(()=>({items:[]})),
      api("/api/integrations").catch(()=>({sources:[]})),
      api("/api/projects").catch(()=>({projects:[]})),
    ]);
    snapshot={workers:state.workers||[],tasks:state.tasks||[]};
    events=ev.events||[];
    workspaceFeed=ws.items||[];
    integrations=providers.sources||[];
    projectFeed=Array.isArray(projects)?projects:
      Array.isArray(projects.projects)?projects.projects:[];
    connectedUi(true);syncUI();
  }catch(error){
    if(/Invalid authorization token|HTTP 401/i.test(error.message)){
      sessionStorage.removeItem("oagent_token");token="";connectedUi(false);
      notice("Operator token rejected. Reconnect with the correct token.");
    }else notice("Unable to refresh: "+error.message);
  }finally{refreshing=false;}
}
function dialogResult(dialog){
  // Reset the previous decision: pressing Escape must never reuse an earlier approval.
  dialog.returnValue="cancel";
  return new Promise(resolve=>{
    const onClose=()=>{dialog.removeEventListener("close",onClose);resolve(dialog.returnValue);};
    dialog.addEventListener("close",onClose,{once:true});
    dialog.showModal();
  });
}
async function confirmAction(title,body,submit="Continue"){
  $("confirmTitle").textContent=title;
  $("confirmText").textContent=body;
  $("confirmAccept").textContent=submit;
  return (await dialogResult($("confirmDialog")))==="confirm";
}
async function requestFilename(title,description,current=""){
  $("inputTitle").textContent=title;
  $("inputDesc").textContent=description;
  $("inputFilename").value=current;
  const decision=await dialogResult($("inputDialog"));
  if(decision!=="confirm")return null;
  const value=$("inputFilename").value.trim();
  if(!FOLDER_NAME.test(value) || value.startsWith(".")){
    notice("Use a filename such as notes.md, without paths, spaces or hidden names.");
    return null;
  }
  return value;
}
async function relay(op,path,{content,expectedHash,newPath}={}){
  if(!activeWorker)throw Error("Select a connected VS Code workspace.");
  const queued=await api("/api/vscode/files/request",{
    method:"POST",body:{workerId:activeWorker,op,path,
      ...(content!==undefined?{content}:{}),
      ...(expectedHash?{expectedHash}:{}),
      ...(newPath?{newPath}:{})}});
  if(!queued.id)throw Error("Backend did not create a workspace request.");
  for(let n=0;n<55;n++){
    await new Promise(resolve=>setTimeout(resolve,1000));
    const job=await api("/api/vscode/files/"+encodeURIComponent(queued.id));
    if(job.state==="failed")throw Error(job.error||"VS Code operation failed");
    if(job.state==="completed")return job.result||{};
  }
  throw Error("VS Code has not responded. Verify the enrolled editor is connected.");
}
function fileBusy(value){
  loadingFile=value;
  for(const id of ["folderUp","folderRefresh","newFile","openWorkspace",
    "editFile","saveFile","renameFile","deleteFile"]){
    const el=$(id);if(!el)continue;
    if(value)el.disabled=true;
  }
  if(!value)setFileActions();
}
function setFileActions(){
  const active=!!openedFile && !loadingFile;
  $("editFile").disabled=!active||openedFile.readOnly;
  $("saveFile").disabled=!active||openedFile.readOnly||$("fileEditor").readOnly;
  $("renameFile").disabled=!active||openedFile.readOnly;
  $("deleteFile").disabled=!active||openedFile.readOnly;
  $("newFile").disabled=!activeWorker||loadingFile;
  $("folderRefresh").disabled=!activeWorker||loadingFile;
  $("folderUp").disabled=!activeWorker||loadingFile||!activeFolder;
  $("openWorkspace").disabled=!workspaceFeed.length||loadingFile;
}
function clearFile(){
  openedFile=null;
  $("fileTitle").textContent="Choose a file";
  $("fileHint").textContent="Select a source file from your enrolled folder. File text is temporary and is not stored in task history.";
  $("fileEditor").value="";
  $("fileEditor").readOnly=true;
  $("fileStatus").textContent="Choose a file";
  setFileActions();
}
async function chooseWorkspace(id){
  if(!workspaceFeed.some(w=>w.workerId===id))throw Error("Workspace is no longer online.");
  if(loadingFile)return;
  activeWorker=id;
  activeFolder="";
  clearFile();
  await loadFolder("");
}
async function loadFolder(path){
  if(loadingFile)return;
  fileBusy(true);
  const root=$("fileList");
  root.replaceChildren(create("div","Loading the real workspace folder…","empty"));
  try{
    const data=await relay("list",path);
    activeFolder=path;
    $("folderName").textContent=path?"/"+path:"Project root";
    root.replaceChildren();
    const dirs=Array.isArray(data.entries)?data.entries:[];
    for(const entry of dirs){
      const row=create("button",undefined,"file-row");
      row.type="button";
      const folder=entry.type==="directory";
      row.append(create("span",folder?"▣":"≡","file-kind"),
        create("span",entry.name),create("span","›","file-arrow"));
      row.addEventListener("click",async()=>{
        try{if(folder)await loadFolder(entry.path);else await openFile(entry.path);}
        catch(e){notice(e.message);}
      });
      root.append(row);
    }
    if(!dirs.length)root.append(create("div","This folder has no accessible files.","empty"));
    if(data.truncated)root.append(create("p","Showing the first 150 entries. Open a subfolder to continue.","hint"));
  }catch(error){
    root.replaceChildren(create("div",error.message,"empty"));
    notice(error.message);
  }finally{fileBusy(false);}
}
async function openFile(path){
  if(loadingFile)return;
  fileBusy(true);
  try{
    const data=await relay("read",path);
    openedFile={path,hash:data.hash,original:data.content||"",
      readOnly:!!data.readOnly};
    $("fileTitle").textContent=path.split("/").at(-1);
    $("fileEditor").value=openedFile.original;
    $("fileEditor").readOnly=true;
    $("fileStatus").textContent=openedFile.readOnly?
      "Read only · local edits pending":"Source loaded";
    $("fileHint").textContent=path+(openedFile.readOnly?
      " · Save local unsaved changes in VS Code first.":" · Change preview and source version verification available.");
  }catch(error){notice(error.message);}finally{fileBusy(false);}
}
function proposedDiff(){
  if(!openedFile)return"";
  const before=openedFile.original.split("\n"),after=$("fileEditor").value.split("\n");
  const diff=[];
  for(let i=0;i<Math.max(before.length,after.length);i++){
    if(before[i]===after[i])continue;
    if(before[i]!==undefined)diff.push("- "+(i+1)+": "+before[i]);
    if(after[i]!==undefined)diff.push("+ "+(i+1)+": "+after[i]);
    if(diff.length>32){diff.push("… Additional changes not shown");break;}
  }
  return diff.join("\n");
}
async function saveFile(){
  if(!openedFile||openedFile.readOnly||loadingFile)return;
  const diff=proposedDiff();
  if(!diff){notice("No changes to save.");return;}
  if(!await confirmAction("Save changes to laptop?",
    "File: "+openedFile.path+"\n\n"+diff+
    "\n\nVS Code must have the 30-minute edit permission enabled. A changed file version is rejected.",
    "Save changes"))return;
  fileBusy(true);
  try{
    const result=await relay("write",openedFile.path,{
      content:$("fileEditor").value,expectedHash:openedFile.hash});
    notice(result.saved?"Saved to the real VS Code project.":"The editor did not confirm a save.");
    await refreshFolderAfterAction();
  }catch(error){notice(error.message,12)}
  finally{fileBusy(false);}
}
async function refreshFolderAfterAction(){
  const folder=activeFolder;
  // Reset before the view is reloaded; callers still own the busy flag.
  openedFile=null;
  clearFile();
  return folder;
}
async function createFile(){
  const filename=await requestFilename("Create a new file",
    "Enter the filename inside the current workspace folder.");
  if(!filename)return;
  const path=[activeFolder,filename].filter(Boolean).join("/");
  if(!await confirmAction("Create file on laptop?",
    "Create a new empty text file: "+path+
    "\n\nThis requires the local 30-minute editing permission.",
    "Create file"))return;
  fileBusy(true);
  try{const result=await relay("create",path,{content:""});
    notice(result.created?"File created.":"File creation not confirmed.");}
  catch(e){notice(e.message,12);}
  finally{fileBusy(false);}
  await loadFolder(activeFolder);
}
async function renameFile(){
  if(!openedFile)return;
  const initial=openedFile.path.split("/").at(-1);
  const newName=await requestFilename("Rename file",
    "Rename the existing source file inside the same folder.",initial);
  if(!newName||initial===newName)return;
  const newPath=[openedFile.path.split("/").slice(0,-1).join("/"),newName].filter(Boolean).join("/");
  if(!await confirmAction("Rename this file?",
    "From: "+openedFile.path+"\nTo: "+newPath+
    "\n\nThe operation will be rejected if the file changed or the destination exists.",
    "Rename file"))return;
  fileBusy(true);
  try{const result=await relay("rename",openedFile.path,{
    newPath,expectedHash:openedFile.hash});
    notice(result.renamed?"File renamed successfully.":"Rename was not confirmed.");
    clearFile();
  }catch(e){notice(e.message,12)}finally{fileBusy(false);}
  await loadFolder(activeFolder);
}
async function deleteFile(){
  if(!openedFile)return;
  if(!await confirmAction("Move file to Trash?",
    "File: "+openedFile.path+
    "\n\nThis action may not be undoable. VS Code will request another local confirmation before moving it to Trash.",
    "Move to Trash"))return;
  fileBusy(true);
  try{const result=await relay("delete",openedFile.path,{expectedHash:openedFile.hash});
    notice(result.deleted?"Delete request completed in VS Code.":"Delete was not confirmed.");
    clearFile();
  }catch(e){notice(e.message,12)}finally{fileBusy(false);}
  await loadFolder(activeFolder);
}

// An owner-only live desktop. Viewing is separate from remote input consent.
// The browser receives JPEG blobs only over authenticated, same-origin HTTP.
let desktopState=null,desktopInput=null,desktopSequence=-1,desktopObjectUrl=null;
let desktopBusy=false,desktopTick=0,desktopSending=false;
const desktopQueue=[];
function clearDesktopPreview(){
  if(desktopObjectUrl){URL.revokeObjectURL(desktopObjectUrl);desktopObjectUrl=null;}
  $("desktopImage").removeAttribute("src");
  $("desktopImage").hidden=true;
  $("desktopPlaceholder").hidden=false;
  desktopSequence=-1;
}
function updateDesktopControls(){
  const fresh=desktopState?.fresh===true;
  const paired=desktopInput?.paired===true && desktopInput?.helperOnline===true;
  $("desktopLiveStatus").textContent=fresh?"Receiving frames":
    desktopState?.capturing?"Waiting for fresh frame":"Not sharing";
  $("desktopInputStatus").textContent=paired?"Pointer paired":"Not paired";
  $("desktopPair").disabled=!fresh||paired;
  $("desktopPairCode").disabled=!fresh||paired;
  const canControl=fresh&&paired&&connected;
  for(const btn of document.querySelectorAll("[data-desktop-action]"))btn.disabled=!canControl;
  $("desktopSendText").disabled=!canControl;
  $("desktopStopInput").disabled=!paired;
  $("desktopStopSharing").disabled=!desktopState?.capturing;
  $("desktopTrackpad").style.opacity=canControl?"1":".45";
  $("desktopMetrics").textContent=desktopState?.capturing
    ? "Measured capture: "+(desktopState.estimatedFps??"measuring")+
      " fps · Queued mouse/keyboard actions: "+(desktopInput?.queueDepth??0)
    : "Start a consented browser screen share on your laptop.";
  const ack=desktopInput?.lastInputResult;
  $("desktopInputFeedback").textContent=ack&&canControl
    ? (ack.ok ? "Windows executed your last "+ack.type+" action."
      : "Windows rejected your last "+ack.type+" action. Check the focused window and permissions.")
    : canControl
      ? "Paired for this laptop. Use the touchpad below; never type secrets remotely."
      : "Input unavailable until the laptop is sharing and its visible helper is paired.";
}
async function desktopRefresh(){
  if(!connected||currentView!=="desktop"||document.hidden||desktopBusy)return;
  desktopBusy=true;
  try{
    const check=!desktopState||++desktopTick%3===0;
    if(check){
      [desktopState,desktopInput]=await Promise.all([
        api("/api/screen/status"),api("/api/input/status"),
      ]);
    }
    if(desktopState?.fresh){
      const request=await fetch("/api/screen/frame?after="+desktopSequence,{
        headers:{authorization:"Bearer "+token,accept:"image/jpeg"},
        cache:"no-store",credentials:"omit",redirect:"error",
      });
      if(request.status===200){
        const type=request.headers.get("content-type")||"";
        if(!type.startsWith("image/jpeg"))throw Error("Unexpected image type");
        const bytes=await request.blob();
        if(bytes.size>240000)throw Error("Screen frame exceeded safe preview size");
        const sequence=Number(request.headers.get("x-oagent-frame-sequence"));
        if(!Number.isSafeInteger(sequence)||sequence<1)
          throw Error("Screen frame sequence was invalid");
        const nextUrl=URL.createObjectURL(bytes);
        const previous=desktopObjectUrl;
        desktopObjectUrl=nextUrl;
        $("desktopImage").src=nextUrl;
        $("desktopImage").hidden=false;
        $("desktopPlaceholder").hidden=true;
        desktopSequence=sequence;
        if(previous)URL.revokeObjectURL(previous);
      }else if(request.status===404){
        clearDesktopPreview();
      }else if(request.status!==204) {
        throw Error("Screen preview returned HTTP "+request.status);
      }
    }else{
      clearDesktopPreview();
    }
    updateDesktopControls();
  }catch(error){
    $("desktopMetrics").textContent="Screen refresh failed: "+error.message;
    if(/401|403/.test(error.message))desktopQueue.length=0;
  }finally{desktopBusy=false;}
}
function queueDesktopAction(actionData){
  if(!connected||currentView!=="desktop"||
      desktopInput?.paired!==true||desktopState?.fresh!==true){
    notice("Pair the visible Windows helper and share a fresh screen first.");
    return;
  }
  const action={...actionData};
  if(action.type==="move"&&desktopQueue.at(-1)?.type==="move"){
    const prev=desktopQueue.at(-1);
    const dx=prev.dx+action.dx,dy=prev.dy+action.dy;
    if(Math.abs(dx)<=150&&Math.abs(dy)<=150){
      prev.dx=dx;prev.dy=dy;
    }else desktopQueue.push(action);
  }else desktopQueue.push(action);
  if(desktopQueue.length>36&&action.type==="move")desktopQueue.pop();
  if(!desktopSending)void drainDesktopQueue();
}
async function drainDesktopQueue(){
  desktopSending=true;
  try{
    while(desktopQueue.length&&connected&&currentView==="desktop"&&
      desktopInput?.paired&&desktopState?.fresh){
      const action=desktopQueue.shift();
      try{
        await api("/api/input/action",{method:"POST",body:action});
      }catch(error){
        if(error.message.includes("rate limit")){
          await new Promise(resolve=>setTimeout(resolve,70));
          try {await api("/api/input/action",{method:"POST",body:action});}
          catch(err){if(action.type!=="move")notice(err.message);}
        }else if(action.type!=="move")notice(error.message);
      }
      await new Promise(resolve=>setTimeout(resolve,25));
    }
  }finally{desktopSending=false;}
}
let desktopTouch=null;
const trackpad=$("desktopTrackpad");
trackpad.addEventListener("pointerdown",event=>{
  if(desktopInput?.paired!==true||!desktopState?.fresh)return;
  event.preventDefault();
  trackpad.setPointerCapture(event.pointerId);
  desktopTouch={id:event.pointerId,x:event.clientX,y:event.clientY,
    total:0};
});
trackpad.addEventListener("pointermove",event=>{
  const touch=desktopTouch;
  if(!touch||event.pointerId!==touch.id)return;
  event.preventDefault();
  const dx=event.clientX-touch.x,dy=event.clientY-touch.y;
  desktopTouch={...touch,x:event.clientX,y:event.clientY,
    total:touch.total+Math.abs(dx)+Math.abs(dy)};
  const moveX=Math.max(-150,Math.min(150,Math.round(dx*1.5)));
  const moveY=Math.max(-150,Math.min(150,Math.round(dy*1.5)));
  if(moveX||moveY)queueDesktopAction({type:"move",dx:moveX,dy:moveY});
});
const endTrack=event=>{
  if(!desktopTouch||event.pointerId!==desktopTouch.id)return;
  if(desktopTouch.total<8)queueDesktopAction({type:"click",button:"left"});
  desktopTouch=null;
};
trackpad.addEventListener("pointerup",endTrack);
trackpad.addEventListener("pointercancel",()=>{desktopTouch=null;});
trackpad.addEventListener("keydown",event=>{
  if(event.key==="Enter"||event.key===" "){
    event.preventDefault();
    queueDesktopAction({type:"click",button:"left"});
  }
});
$("desktopPair").addEventListener("click",async()=>{
  const code=$("desktopPairCode").value.trim();
  if(!/^\d{8}$/.test(code)){notice("Enter the exact 8-digit code displayed on the laptop.");return;}
  if(!await confirmAction("Enable supervised Windows input?",
    "You must have enabled the visible REMOTE-CONTROL.cmd helper on the trusted Windows laptop. "
    +"A paired session can click, type and use the desktop for up to 20 minutes. "
    +"Never enter passwords or private tokens through remote input.","Pair this device"))return;
  try{
    await api("/api/input/pair",{method:"POST",body:{code}});
    $("desktopPairCode").value="";
    desktopTick=2;
    await desktopRefresh();
    notice("Windows remote input paired for this temporary session.");
  }catch(error){notice(error.message);}
});
$("desktopRefresh").addEventListener("click",()=>{desktopTick=2;void desktopRefresh();});
$("desktopStopInput").addEventListener("click",async()=>{
  try{
    await api("/api/input/stop",{method:"POST"});
    desktopQueue.length=0;desktopInput=null;
    updateDesktopControls();
    notice("Windows input stopped and pairing revoked.");
    await desktopRefresh();
  }catch(error){notice(error.message);}
});
$("desktopStopSharing").addEventListener("click",async()=>{
  if(!await confirmAction("Stop laptop screen sharing?",
    "This revokes the capture lease and any paired input. The laptop browser's sharing indicator will stop.","Stop sharing"))return;
  try{
    await api("/api/screen/stop",{method:"POST"});
    desktopQueue.length=0;
    desktopState=null;desktopInput=null;
    clearDesktopPreview();updateDesktopControls();
    notice("Screen sharing stopped.");
  }catch(error){notice(error.message);}
});
$("desktopCopyCapture").addEventListener("click",async()=>{
  try{
    await navigator.clipboard.writeText(new URL("/screen-capture",location.origin).href);
    notice("Laptop screen picker URL copied. Open on your trusted computer.");
  }catch{notice("Browser denied clipboard access. Open /screen-capture on your laptop.");}
});
$("desktopSendText").addEventListener("click",()=>{
  const content=$("desktopTypeText").value;
  if(!content||content.length>300)return notice("Enter up to 300 test-only characters.");
  queueDesktopAction({type:"text",text:content});
  $("desktopTypeText").value="";
});
for(const element of document.querySelectorAll("[data-desktop-action]")){
  element.addEventListener("click",()=>{
    const [type,value]=element.dataset.desktopAction.split(":");
    const data=type==="click"?{type,button:value}:
      type==="key"?{type,key:value}:
      type==="scroll"?{type,steps:Number(value)}:
      {type:"shortcut",name:value};
    queueDesktopAction(data);
  });
}
setInterval(()=>{if(currentView==="desktop")void desktopRefresh();},750);
document.addEventListener("visibilitychange",()=>{
  if(!document.hidden && currentView==="desktop")void desktopRefresh();
});

// Event registration is explicit: no buttons without an implementation.
for(const button of document.querySelectorAll(".nav-link"))
  button.addEventListener("click",()=>navigate(button.dataset.view));
for(const button of document.querySelectorAll("[data-navigate]"))
  button.addEventListener("click",()=>navigate(button.dataset.navigate));
$("menuToggle").addEventListener("click",()=> $("sidebar").classList.toggle("open"));
$("authForm").addEventListener("submit",async event=>{
  event.preventDefault();
  const supplied=$("token").value.trim();
  if(supplied.length<24){notice("Operator token must be at least 24 characters.");return;}
  token=supplied;
  sessionStorage.setItem("oagent_token",token);
  await refresh();
  $("token").value="";
});
$("disconnect").addEventListener("click",()=>{
  token="";sessionStorage.removeItem("oagent_token");
  connectedUi(false);activeWorker="";workspaceFeed=[];openedFile=null;
  navigate("overview");notice("Disconnected this browser tab.");
});
$("refresh").addEventListener("click",refresh);
$("workerSelect").addEventListener("change",updateAvailableTaskKinds);
$("taskForm").addEventListener("submit",async event=>{
  event.preventDefault();
  try{
    const workerId=$("workerSelect").value,kind=$("kind").value;
    if(!workerId||!kind)throw Error("Choose an online machine and supported operation.");
    await api("/api/tasks",{method:"POST",
      headers:{"idempotency-key":crypto.randomUUID()},
      body:{workerId,kind}});
    notice("Task submitted to your enrolled worker.");
    await refresh();
  }catch(e){notice(e.message)}
});
$("openWorkspace").addEventListener("click",async()=>{
  try{await chooseWorkspace($("workspaceSelect").value);}catch(e){notice(e.message);}
});
$("folderRefresh").addEventListener("click",()=>loadFolder(activeFolder));
$("folderUp").addEventListener("click",()=>{
  const parts=activeFolder.split("/");parts.pop();void loadFolder(parts.join("/"));
});
$("newFile").addEventListener("click",createFile);
$("editFile").addEventListener("click",()=>{
  if(!openedFile||openedFile.readOnly)return;
  $("fileEditor").readOnly=false;$("fileEditor").focus();
  $("fileStatus").textContent="Editing · unsaved on phone";
  setFileActions();
});
$("saveFile").addEventListener("click",saveFile);
$("renameFile").addEventListener("click",renameFile);
$("deleteFile").addEventListener("click",deleteFile);
setInterval(refresh,15000);
if(token)void refresh();else connectedUi(false);
