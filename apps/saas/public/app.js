"use strict";
const $ = id => document.getElementById(id);
const create = (tag,text,className) => {
  const element=document.createElement(tag);
  if(text!==undefined)element.textContent=String(text);
  if(className)element.className=className;
  return element;
};
const NONE = Object.freeze([]);
let config=null, accessToken=null, expiresAt=0,refreshing=false;
let state={devices:[],runs:[],approvals:[],audit:[],role:"viewer",workspaces:[],members:[],tenantId:null};
const WORKSPACE_ID=/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i;
let workspaceId=sessionStorage.getItem("oagent_active_workspace");
if(workspaceId && !WORKSPACE_ID.test(workspaceId)){
  sessionStorage.removeItem("oagent_active_workspace");workspaceId=null;
}
let activeView="overview",pendingPair=sessionStorage.getItem("oagent_pending_pair")||null;
let review=null, noticeTimeout=null;
const ACTIVE=new Set(["queued","running","waiting_for_tool","needs_recovery"]);
const TOOL_NAMES={
  workspace_inventory:"Workspace inventory",
  claude_agent_turn:"Claude Agent SDK",
  copilot_sdk_turn:"GitHub Copilot SDK",
  codex_cli_turn:"OpenAI Codex CLI",
};
const statusText=status=>String(status||"unknown").replaceAll("_"," ");
const dateText=value=>{
  const ms=Date.parse(value);
  return Number.isFinite(ms)?new Date(ms).toLocaleString():"Unknown";
};
const fresh=device=>device && !device.revoked_at &&
  Date.parse(device.last_seen_at)>Date.now()-120000;
function notice(message,isError=false){
  $("notice").textContent=String(message||"");
  $("notice").classList.toggle("warning",isError);
  if(noticeTimeout)clearTimeout(noticeTimeout);
  if(message)noticeTimeout=setTimeout(()=>{$("notice").textContent=""},8000);
}
function badge(value){
  const status=String(value||"unknown"),label=statusText(status);
  return create("span",label,"pill "+status.replace(/[^a-z_]/gi,""));
}
function empty(target,message){
  target.replaceChildren(create("p",message,"empty"));
}
function entry(title,description,status){
  const node=create("article",undefined,"entry");
  const top=create("div",undefined,"entry-head");
  top.append(create("strong",title,"entry-title"));
  if(status)top.append(badge(status));
  node.append(top);
  if(description)node.append(create("p",description,"entry-detail"));
  return node;
}
function action(node,text,fn,style="secondary"){
  const b=create("button",text,"button "+style);
  b.type="button";
  b.addEventListener("click",async()=>{
    if(b.disabled)return;
    b.disabled=true;
    try{await fn();}catch(error){notice(error.message,true);}
    finally{b.disabled=false;}
  });
  node.append(b);
  return b;
}
function navigate(view){
  if(!["overview","approvals","runs","devices","audit","team"].includes(view))return;
  activeView=view;
  for(const panel of document.querySelectorAll("[data-panel]"))
    panel.hidden=panel.dataset.panel!==view;
  for(const button of document.querySelectorAll("[data-view]")){
    const selected=button.dataset.view===view;
    button.classList.toggle("active",selected);
    if(selected)button.setAttribute("aria-current","page");
    else button.removeAttribute("aria-current");
  }
  $("viewName").textContent=({
    overview:"Overview",approvals:"Action inbox",
    runs:"Agent runs",devices:"Connected devices",
    audit:"Security activity",team:"Team & workspaces",
  })[view];
  $("sidebar").classList.remove("open");
  window.scrollTo({top:0,behavior:"instant"});
}
const base64url=bytes=>btoa(String.fromCharCode(...bytes))
  .replace(/\+/g,"-").replace(/\//g,"_").replace(/=+$/,"");
const randomUrl=length=>base64url(crypto.getRandomValues(new Uint8Array(length)));
async function shaChallenge(verifier){
  return base64url(new Uint8Array(await crypto.subtle.digest(
    "SHA-256",new TextEncoder().encode(verifier))));
}
async function authorize(){
  if(!config?.authEnabled){
    notice("Identity provider not configured. Contact your O-AGENT administrator.",true);
    return;
  }
  const verifier=randomUrl(48),stateNonce=randomUrl(24);
  sessionStorage.setItem("oagent_pkce_state",stateNonce);
  sessionStorage.setItem("oagent_pkce_verifier",verifier);
  const target=new URL(config.authorizationEndpoint);
  for(const [key,value] of Object.entries({
    response_type:"code",client_id:config.clientId,
    redirect_uri:config.redirectUri,scope:config.scope,
    state:stateNonce,code_challenge:await shaChallenge(verifier),
    code_challenge_method:"S256",audience:config.audience,
  }))target.searchParams.set(key,value);
  location.assign(target.href);
}
async function exchangeCallback(){
  const url=new URL(location.href);
  const code=url.searchParams.get("code"),stateReturned=url.searchParams.get("state");
  const oauthError=url.searchParams.get("error");
  if(!code&&!oauthError)return;
  url.searchParams.delete("code");url.searchParams.delete("state");
  url.searchParams.delete("error");url.searchParams.delete("error_description");
  history.replaceState(null,"",url.pathname+url.search+url.hash);
  if(oauthError)throw Error("Identity provider refused sign-in. Check your account permissions.");
  const expected=sessionStorage.getItem("oagent_pkce_state");
  const verifier=sessionStorage.getItem("oagent_pkce_verifier");
  sessionStorage.removeItem("oagent_pkce_state");
  sessionStorage.removeItem("oagent_pkce_verifier");
  if(!expected||!verifier||expected!==stateReturned)
    throw Error("Invalid sign-in state. Begin a new secure login.");
  if(!config?.authEnabled)throw Error("Identity provider is unavailable.");
  const body=new URLSearchParams({
    grant_type:"authorization_code",code,code_verifier:verifier,
    client_id:config.clientId,redirect_uri:config.redirectUri,
  });
  const response=await fetch(config.tokenEndpoint,{
    method:"POST",headers:{"content-type":"application/x-www-form-urlencoded"},
    body,cache:"no-store",redirect:"error",
  });
  const token=await response.json().catch(()=>({}));
  if(!response.ok||typeof token.access_token!=="string"||
      !Number.isFinite(Number(token.expires_in))||
      Number(token.expires_in)<30)
    throw Error("OIDC token exchange failed. Check client, redirect URI and provider CORS setup.");
  // Access tokens are only ever kept in memory. Never localStorage, URLs, or logs.
  accessToken=token.access_token;
  expiresAt=Date.now()+Number(token.expires_in)*1000;
}
function loggedIn(){
  return !!accessToken && expiresAt>Date.now()+5000;
}
function showAuth(connected){
  $("auth").hidden=connected;$("app").hidden=!connected;
}
async function api(path,{method="GET",body,headers}={}){
  if(!loggedIn())throw Error("Session expired. Sign in securely again.");
  const result=await fetch(path,{
    method,headers:{authorization:"Bearer "+accessToken,
      accept:"application/json",
      ...(workspaceId?{"x-oagent-workspace":workspaceId}:{}),
      ...(body!==undefined?{"content-type":"application/json"}:{}),...headers},
    ...(body!==undefined?{body:JSON.stringify(body)}:{}),
    cache:"no-store",redirect:"error",
  });
  const json=await result.json().catch(()=>({}));
  if(result.status===401){
    accessToken=null;expiresAt=0;showAuth(false);
    throw Error("Your session expired. Sign in again.");
  }
  if(!result.ok)throw Error(String(json.error||"HTTP "+result.status));
  return json;
}
function pillConnection(ok){
  $("connectionPill").textContent=ok?"Backend connected":"Not connected";
  $("connectionPill").classList.toggle("online",ok);
  $("sideConnect").textContent=ok?"Secure connection":"Backend unavailable";
  $("sideDot").classList.toggle("online",ok);
}
function renderDevice(node,device){
  const online=fresh(device),state=device.revoked_at?
    "revoked":online?"online":"offline";
  const el=entry(device.name||"Enrolled device",
    "Device "+device.id+" · Last heartbeat "+dateText(device.last_seen_at),state);
  const caps=Array.isArray(device.capabilities)?device.capabilities:[];
  el.append(create("p",caps.length?
    caps.map(x=>TOOL_NAMES[x]||x).join(" · "):
    "No provider execution capability advertised","entry-detail"));
  if(device.workspace_root)el.append(create("p",
    "Enrolled workspace: "+device.workspace_root,"entry-detail"));
  if(!device.revoked_at && state.role==="owner"){
    const buttons=create("div",undefined,"entry-actions");
    action(buttons,"Revoke device",async()=>{
      const agree=await reviewExact({
        title:"Revoke trusted device?",
        description:"The device will lose its authorization immediately.",
        detail:"Name: "+device.name+"\nDevice ID: "+device.id+
          "\n\nThis cannot be undone. The device must enroll again.",
        buttons:"revoke",
      });
      if(!agree)return;
      await api("/v1/devices/"+encodeURIComponent(device.id)+"/revoke",
        {method:"POST",body:{}});
      notice("Device authorization revoked.");
      await refresh();
    },"danger");
    el.append(buttons);
  }
  node.append(el);
}
function renderRun(node,run){
  const title=(TOOL_NAMES[run.kind]||run.kind||"Agent")+" · "+
    (run.mode==="workspace_write"?"Edits":"Read only");
  const el=entry(title,
    "Device "+run.device_id+" · "+dateText(run.created_at),run.status);
  if(run.error)el.append(create("p",run.error,"entry-detail"));
  const actions=create("div",undefined,"entry-actions");
  action(actions,"View actual activity",async()=>{
    const exact=await api("/v1/runs/"+encodeURIComponent(run.id));
    const events=await api("/v1/runs/"+encodeURIComponent(run.id)+"/events?after=0");
    const items=Array.isArray(events.events)?events.events:[];
    await reviewExact({
      title:"Verified agent run",
      description:"Provider: "+(TOOL_NAMES[exact.kind]||exact.kind)+
        " · "+statusText(exact.status),
      detail:"Run ID: "+exact.id+"\nWorkspace: "+(exact.cwd||"enrolled root")+
        "\nSession: "+(exact.session_id||"new provider session")+
        "\nPrompt: "+exact.prompt+
        "\n\nRecent real activity:\n"+items.map(e=>e.kind+": "+e.text).join("\n")+
        (exact.error?"\n\nFailure: "+exact.error:"")+
        (exact.result?"\n\nProvider result:\n"+JSON.stringify(exact.result,null,2):""),
      buttons:"close",
    });
  });
  if(state.role!=="viewer" && ["waiting_for_approval","queued"].includes(run.status)){
    action(actions,"Cancel pending run",async()=>{
      const decision=await reviewExact({
        title:"Cancel the pending task?",
        description:"A queued task can be cancelled before its worker claims it.",
        detail:"Run: "+run.id+"\nStatus: "+statusText(run.status),
        buttons:"confirm",confirmLabel:"Cancel pending run",
      });
      if(!decision)return;
      await api("/v1/runs/"+encodeURIComponent(run.id)+"/cancel",{
        method:"POST",body:{},
      });
      notice("Pending run cancelled.");await refresh();
    },"danger");
  }
  if(state.role!=="viewer" && run.status==="needs_recovery"){
    action(actions,"Resolve interrupted run",async()=>{
      const exact=await api("/v1/runs/"+encodeURIComponent(run.id));
      const confirmed=await reviewExact({
        title:"A provider run was interrupted",
        description:"Inspect your provider and project state before proceeding. O-AGENT never silently retries a potentially side-effecting command.",
        detail:"Run: "+exact.id+"\nProvider: "+exact.kind+
          "\nWorkspace: "+exact.cwd+"\nLast status: "+exact.status+
          "\n\nMark this interrupted run failed WITHOUT replaying it?",
        buttons:"confirm",confirmLabel:"Mark run failed",
      });
      if(!confirmed)return;
      await api("/v1/runs/"+encodeURIComponent(run.id)+"/resolve-interrupted",{
        method:"POST",body:{confirm:"MARK_INTERRUPTED_RUN_FAILED"},
      });
      notice("Interrupted run marked failed. No replay was performed.");
      await refresh();
    },"danger");
  }
  el.append(actions);node.append(el);
}
function renderApproval(node,approval){
  const el=entry(approval.kind==="tool"?"Agent tool permission":"Supervised agent task",
    approval.description, "pending");
  el.append(create("p","Device "+approval.device_id+" · Expires "+
    dateText(approval.expires_at),"entry-detail"));
  const actions=create("div",undefined,"entry-actions");
  const reviewButton=action(actions,state.role==="viewer"?"Viewer cannot decide":"Review exact request",
    ()=>approveDialog(approval),"primary");
  if(state.role==="viewer")reviewButton.disabled=true;
  if(approval.actionable===false){
    reviewButton.disabled=true;
    el.append(create("p",approval.unavailableReason||
      "The original worker is unavailable. Refresh to recheck.","entry-detail"));
  }
  el.append(actions);node.append(el);
}
async function approveDialog(item){
  if(Date.parse(item.expires_at)<=Date.now()){
    notice("Approval expired. Refresh your inbox.",true);await refresh();return;
  }
  // Fetch the original run immediately before prompting for a decision.
  const run=await api("/v1/runs/"+encodeURIComponent(item.run_id));
  if(run.id!==item.run_id||run.device_id!==item.device_id ||
      !(item.kind==="tool"?run.status==="waiting_for_tool":
        run.status==="waiting_for_approval")){
    notice("This action changed. Refresh to inspect the latest request.",true);
    await refresh();return;
  }
  const details="Provider: "+(TOOL_NAMES[run.kind]||run.kind)+
    "\nWorker: "+run.device_id+
    "\nPermission mode: "+run.mode+
    "\nWorkspace: "+(run.cwd||"Enrolled root")+
    "\nSession: "+(run.session_id||"new session")+
    "\nAction checksum: "+item.action_hash+
    "\nExpires: "+dateText(item.expires_at)+
    "\n\nExact request:\n"+item.description+
    "\n\nOriginal agent prompt:\n"+run.prompt;
  const decision=await reviewExact({
    title:item.kind==="tool"?"Tool permission review":"Approve supervised run?",
    description:"One-time decision. O-AGENT cannot bypass provider permissions.",
    detail:details,buttons:"approve-deny",
  });
  if(decision===null)return;
  // Expiration and action hash are enforced in the server transaction again.
  await api("/v1/approvals/"+encodeURIComponent(item.id)+"/decision",{
    method:"POST",body:{approve:decision,expectedActionHash:item.action_hash},
  });
  notice(decision?"Approval recorded. Watch the run for actual progress.":
    "Request denied.");
  await refresh();
}
function reviewExact({title,description,detail,buttons="close",confirmLabel="Confirm action"}){
  if(review)return Promise.resolve(null);
  $("reviewTitle").textContent=title;
  $("reviewDescription").textContent=description;
  $("reviewDetails").textContent=detail;
  $("reviewApprove").textContent=buttons==="revoke"?"Revoke device":
    buttons==="confirm"?confirmLabel:"Approve once";
  $("reviewApprove").hidden=buttons==="close";
  $("reviewDeny").hidden=buttons!=="approve-deny";
  $("reviewCancel").textContent=buttons==="close"?"Close":"Cancel";
  $("reviewDialog").showModal();
  return new Promise(resolve=>{
    let settled=false;
    function done(result){
      if(settled)return;settled=true;
      $("reviewDialog").removeEventListener("close",onClose);
      $("reviewApprove").removeEventListener("click",yes);
      $("reviewDeny").removeEventListener("click",no);
      $("reviewCancel").removeEventListener("click",cancel);
      if($("reviewDialog").open)$("reviewDialog").close();
      review=null;resolve(result);
    }
    const yes=()=>done(true),no=()=>done(false),
      cancel=()=>done(null),onClose=()=>done(null);
    review={close:cancel};
    $("reviewApprove").addEventListener("click",yes);
    $("reviewDeny").addEventListener("click",no);
    $("reviewCancel").addEventListener("click",cancel);
    $("reviewDialog").addEventListener("close",onClose,{once:true});
  });
}
async function startSupervisedRun(event){
  event.preventDefault();
  const deviceId=$("deviceSelect").value,kind=$("providerSelect").value;
  const mode=$("modeSelect").value,prompt=$("prompt").value.trim(),
    cwd=$("cwd").value.trim(),sessionId=$("sessionId").value.trim();
  if(!deviceId||!kind)throw Error("Select an online compatible device.");
  const selected=state.devices.find(x=>x.id===deviceId);
  if(!fresh(selected)||!selected.capabilities?.includes(kind))
    throw Error("Device is not online or no longer supports the selected provider.");
  const description="Device: "+selected.name+"\nProvider: "+(TOOL_NAMES[kind]||kind)+
    "\nMode: "+mode+"\nWorkspace: "+(cwd||"enrolled root")+
    "\nProvider session: "+(sessionId||"new session")+
    "\n\nPrompt:\n"+prompt+
    "\n\nSubmitting creates an approval request; it does NOT execute automatically.";
  const confirmed=await reviewExact({
    title:"Request a supervised agent run",
    description:"Review exact destination, provider and permission mode.",
    detail:description,buttons:"confirm",confirmLabel:"Request approval",
  });
  if(!confirmed)return;
  const created=await api("/v1/runs",{method:"POST",
    headers:{"idempotency-key":crypto.randomUUID()},
    body:{deviceId,kind,mode,prompt,cwd,...(sessionId?{sessionId}:{})}});
  navigate("approvals");
  notice("Supervised request created. It must be approved separately before execution.");
  await refresh();
  return created;
}
function updateProviderOptions(){
  const device=state.devices.find(x=>x.id===$("deviceSelect").value);
  const old=$("providerSelect").value;
  $("providerSelect").replaceChildren();
  for(const type of Array.isArray(device?.capabilities)?device.capabilities:[]){
    if(!Object.hasOwn(TOOL_NAMES,type))continue;
    const opt=create("option",TOOL_NAMES[type]);opt.value=type;
    $("providerSelect").append(opt);
  }
  if([...$("providerSelect").options].some(x=>x.value===old))
    $("providerSelect").value=old;
  $("submitRun").disabled=!fresh(device)||!$("providerSelect").options.length;
}
function renderAudit(node,record){
  const label=String(record.action||"security event").replaceAll("."," · ");
  const el=entry(label,"Actor: "+(record.actor||"unknown")+
    " · "+dateText(record.created_at));
  if(record.target_id)el.append(create("p",
    "Related request: "+record.target_id,"entry-detail"));
  node.append(el);
}
function render(){
  const {devices,runs,approvals,audit}=state;
  $("statDevices").textContent=String(devices.filter(fresh).length);
  $("statRunning").textContent=String(runs.filter(x=>ACTIVE.has(x.status)).length);
  $("statApprovals").textContent=String(approvals.length);
  $("statCompleted").textContent=String(runs.filter(x=>x.status==="completed").length);
  $("sidePending").textContent=String(approvals.length);
  const recentApprovals=$("overviewApprovals");recentApprovals.replaceChildren();
  if(approvals.length)for(const a of approvals.slice(0,4))renderApproval(recentApprovals,a);
  else empty(recentApprovals,"All caught up. No genuine pending approvals.");
  const recentDevices=$("overviewDevices");recentDevices.replaceChildren();
  if(devices.length)for(const d of devices.slice(0,4))renderDevice(recentDevices,d);
  else empty(recentDevices,"No trusted devices enrolled yet.");
  const recentRuns=$("overviewRuns");recentRuns.replaceChildren();
  if(runs.length)for(const r of runs.slice(0,5))renderRun(recentRuns,r);
  else empty(recentRuns,"No real agent runs have been requested.");
  const fullApprovals=$("approvalList");fullApprovals.replaceChildren();
  if(approvals.length)for(const a of approvals)renderApproval(fullApprovals,a);
  else empty(fullApprovals,"No pending requests. They appear only when agents really ask.");
  const fullRuns=$("runList");fullRuns.replaceChildren();
  if(runs.length)for(const r of runs)renderRun(fullRuns,r);
  else empty(fullRuns,"Run history will appear after a supervised task is requested.");
  const allDevices=$("deviceList");allDevices.replaceChildren();
  if(devices.length)for(const d of devices)renderDevice(allDevices,d);
  else empty(allDevices,"Your account has no enrolled device.");
  const auditList=$("auditList");auditList.replaceChildren();
  if(audit.length)for(const event of audit)renderAudit(auditList,event);
  else empty(auditList,"No server-recorded account actions yet.");
  const select=$("deviceSelect"),previous=select.value;
  select.replaceChildren();
  for(const device of devices.filter(fresh)){
    const option=create("option",device.name+" · "+device.id.slice(0,8));
    option.value=device.id;select.append(option);
  }
  if([...select.options].some(x=>x.value===previous))select.value=previous;
  updateProviderOptions();
  const selected=state.devices.find(x=>x.id===select.value);
  if(!$("cwd").value.trim()&&selected?.workspace_root)
    $("cwd").value=selected.workspace_root;
}

function switchWorkspace(next){
  if(!WORKSPACE_ID.test(next)||!state.workspaces.some(w=>w.tenant_id===next))
    throw Error("Choose an authorized workspace");
  workspaceId=next;
  sessionStorage.setItem("oagent_active_workspace",workspaceId);
  state={...state,devices:[],runs:[],approvals:[],audit:[]};
  pillConnection(false);
  void refresh();
}
function renderTeam(){
  const selector=$("workspaceSwitch");
  const previous=workspaceId||state.tenantId;
  selector.replaceChildren();
  for(const item of state.workspaces){
    const option=create("option",(item.display_name||"Private workspace")+" · "+item.role);
    option.value=item.tenant_id;selector.append(option);
  }
  selector.value=previous;
  if(!selector.value && state.tenantId)selector.value=state.tenantId;
  const active=state.workspaces.find(w=>w.tenant_id===state.tenantId);
  $("teamRole").textContent=(active?.display_name||"Selected workspace")+
    " · "+state.role.toUpperCase();
  $("teamAdmin").hidden=state.role!=="owner";
  $("workspaceName").value=active?.display_name||"";
  $("deleteAccount").disabled=state.role!=="owner";
  $("exportAccount").disabled=state.role!=="owner";
  $("pairApprove").disabled=state.role!=="owner";
  $("enableAlerts").disabled=state.role==="viewer";
  for(const element of $("runForm").querySelectorAll("input,select,textarea,button"))
    element.disabled=state.role==="viewer";
  for(const button of document.querySelectorAll('[data-view="audit"]'))
    button.hidden=state.role==="viewer";
  const people=$("teamMemberList");people.replaceChildren();
  if(state.role==="owner"){
    for(const member of state.members){
      const row=entry(member.subject,member.issuer,member.role);
      if(member.role!=="owner"){
        const actions=create("div",undefined,"entry-actions");
        action(actions,"Remove member",async()=>{
          const confirmed=await reviewExact({
            title:"Revoke this member's access?",
            description:"Their access to this shared workspace ends immediately.",
            detail:"Signed identity: "+member.issuer+" / "+member.subject+
              "\nRole: "+member.role,
            buttons:"confirm",confirmLabel:"Remove team member",
          });
          if(!confirmed)return;
          await api("/v1/team/members/remove",{method:"POST",
            body:{issuer:member.issuer,subject:member.subject}});
          notice("Team member access revoked.");await refresh();
        },"danger");
        row.append(actions);
      }
      people.append(row);
    }
    if(!state.members.length)empty(people,"No member records.");
  }
}

async function inspectPairing(){
  if(!pendingPair)return;
  if(!/^oen_[A-Za-z0-9_-]{43}$/.test(pendingPair)){
    pendingPair=null;sessionStorage.removeItem("oagent_pending_pair");
    notice("Invalid pairing link. Create a new enrollment on your computer.",true);
    return;
  }
  try{
    const item=await api("/v1/devices/enrollments/inspect",{
      method:"POST",body:{pairingToken:pendingPair},
    });
    if(item.approved){
      pendingPair=null;sessionStorage.removeItem("oagent_pending_pair");
      notice("This device has already been approved.");
      return;
    }
    $("pairPanel").hidden=false;
    $("pairDescription").textContent="Device: "+item.name+
      " · Confirm the fingerprint matches what your computer displays.";
    $("pairFingerprint").textContent="Fingerprint: "+item.fingerprint;
    $("pairApprove").dataset.fingerprint=item.fingerprint;
  }catch(error){
    pendingPair=null;sessionStorage.removeItem("oagent_pending_pair");
    $("pairPanel").hidden=true;notice(error.message,true);
  }
}
async function refresh(){
  if(!loggedIn()||refreshing||document.hidden)return;
  refreshing=true;$("refresh").disabled=true;
  try{
    const me=await api("/v1/me");
    if(!me.tenantId||!["owner","operator","viewer"].includes(me.role))
      throw Error("Account workspace role was not verified.");
    const [deviceData,runData,approvalData,auditData,workspaceData,memberData]=await Promise.all([
      api("/v1/devices"),api("/v1/runs"),api("/v1/approvals"),
      me.role==="viewer"?Promise.resolve({events:[]}):api("/v1/audit"),
      api("/v1/team/workspaces"),
      me.role==="owner"?api("/v1/team/members"):Promise.resolve({members:[]}),
    ]);
    state={
      tenantId:me.tenantId,role:me.role,
      devices:Array.isArray(deviceData.devices)?deviceData.devices:NONE,
      runs:Array.isArray(runData.runs)?runData.runs:NONE,
      approvals:Array.isArray(approvalData.approvals)?approvalData.approvals:NONE,
      audit:Array.isArray(auditData.events)?auditData.events:NONE,
      workspaces:Array.isArray(workspaceData.workspaces)?workspaceData.workspaces:NONE,
      members:Array.isArray(memberData.members)?memberData.members:NONE,
    };
    render();renderTeam();pillConnection(true);showAuth(true);
    if(navigator.setAppBadge){
      void navigator.setAppBadge(state.approvals.length).catch(()=>{});
    }
  }catch(error){
    pillConnection(false);
    // An unavailable provider must never be displayed as zero approved tasks.
    for(const id of ["statDevices","statRunning","statApprovals","statCompleted"])
      $(id).textContent="—";
    $("sidePending").textContent="!";
    if(workspaceId && /Workspace membership or permission required/.test(error.message)){
      workspaceId=null;sessionStorage.removeItem("oagent_active_workspace");
      notice("Shared workspace access changed. Switched to private workspace. Refresh to reload.",true);
    }else notice("Unable to verify current workspace: "+error.message,true);
  }finally{refreshing=false;$("refresh").disabled=false;}
}
function disconnect(){
  accessToken=null;expiresAt=0;
  state={devices:[],runs:[],approvals:[],audit:[],role:"viewer",workspaces:[],members:[],tenantId:null};
  workspaceId=null;sessionStorage.removeItem("oagent_active_workspace");
  showAuth(false);pillConnection(false);
}
function b64ToBytes(value){
  const raw=value.replace(/-/g,"+").replace(/_/g,"/");
  const padded=raw.padEnd(Math.ceil(raw.length/4)*4,"=");
  return Uint8Array.from(atob(padded),char=>char.charCodeAt(0));
}
async function enableAlerts(){
  if(!loggedIn())throw Error("Sign in first to enable your private alerts.");
  if(!("Notification" in window)||!("serviceWorker" in navigator)||
      !("PushManager" in window))
    throw Error("This browser does not support standard web push. On iPhone, install the app to your Home Screen.");
  const permission=await Notification.requestPermission();
  if(permission!=="granted")throw Error("Browser notification permission was not granted.");
  const push=await api("/v1/push/config");
  if(!push.enabled||!push.vapidPublicKey)
    throw Error("Approval alerts are not configured on this O-AGENT server.");
  const service=await navigator.serviceWorker.ready;
  let subscription=await service.pushManager.getSubscription();
  if(!subscription){
    subscription=await service.pushManager.subscribe({
      userVisibleOnly:true,applicationServerKey:b64ToBytes(push.vapidPublicKey),
    });
  }
  const saved=await api("/v1/push/subscriptions",{
    method:"POST",body:subscription.toJSON(),
  });
  if(saved.subscribed){
    $("enableAlerts").textContent="Alerts enabled for this device";
    notice("Private approval alerts enabled. Delivery depends on the browser and network.");
  }
}
async function disableAlerts(){
  if(!loggedIn())throw Error("Sign in to change browser notifications.");
  if(!("serviceWorker" in navigator))return;
  const service=await navigator.serviceWorker.ready;
  const subscription=await service.pushManager?.getSubscription();
  if(!subscription)return;
  await api("/v1/push/subscriptions",{
    method:"DELETE",body:{endpoint:subscription.endpoint},
  });
  await subscription.unsubscribe();
  $("enableAlerts").textContent="Enable approval alerts";
  notice("Approval alerts are disabled on this phone.");
}
async function signOut(){
  // Do not leave another user's notifications on a shared browser.
  try{await disableAlerts();}catch{
    notice("Push service could not be unsubscribed. Review notification permissions.",true);
  }
  const endpoint=config?.logoutEndpoint;
  disconnect();
  sessionStorage.removeItem("oagent_pending_pair");
  if(endpoint){
    const target=new URL(endpoint);
    target.searchParams.set("client_id",config.clientId);
    target.searchParams.set("post_logout_redirect_uri",config.redirectUri);
    location.assign(target.href);
  }else notice("Signed out locally; identity provider logout is not configured.");
}
async function exportMyAccount(){
  if(!loggedIn())throw Error("Sign in securely to export your own workspace");
  const data=await api("/v1/account/export");
  if(data.format!=="oagent-tenant-export-v1")
    throw Error("Unexpected data export format");
  const blob=new Blob([JSON.stringify(data,null,2)],{
    type:"application/json;charset=utf-8",
  });
  const target=URL.createObjectURL(blob);
  const link=document.createElement("a");
  link.href=target;
  link.download="oagent-workspace-"+new Date().toISOString().slice(0,10)+".json";
  document.body.append(link);
  try{link.click();}
  finally{
    link.remove();
    setTimeout(()=>URL.revokeObjectURL(target),60000);
  }
  notice("Your private workspace export was prepared on this device.");
}
async function deleteMyAccount(){
  const phrase=$("deletePhrase").value;
  if(phrase!=="DELETE_MY_OAGENT_WORKSPACE"||!$("ackLocalData").checked)
    throw Error("Type the exact confirmation and acknowledge remaining local data.");
  await api("/v1/account/delete",{
    method:"POST",body:{confirmation:phrase,acknowledgeLocalData:true},
  });
  $("deleteDialog").close();
  $("deletePhrase").value="";
  $("ackLocalData").checked=false;
  disconnect();
  $("authHint").textContent="Your server-side workspace data was deleted. Provider accounts, local files and backups are separate.";
  $("signIn").disabled=false;
}
async function bootstrap(){
  const hash=location.hash.startsWith("#pair=")?
    location.hash.slice("#pair=".length):null;
  if(hash){
    pendingPair=decodeURIComponent(hash);
    sessionStorage.setItem("oagent_pending_pair",pendingPair);
    history.replaceState(null,"",location.pathname+location.search);
  }
  const requestedView=new URL(location.href).searchParams.get("view");
  if(["overview","approvals","runs","devices","audit","team"].includes(requestedView)){
    navigate(requestedView);
  }
  try{
    const response=await fetch("/v1/public-config",{cache:"no-store"});
    config=await response.json();
    if(!response.ok)throw Error("Workspace configuration unavailable");
    $("signIn").disabled=!config.authEnabled;
    $("authHint").textContent=config.authEnabled?
      "Your administrator's identity provider manages your secure sign-in.":
      "Authentication is not configured on this server. Contact your administrator.";
    await exchangeCallback();
    if(loggedIn()){
      showAuth(true);
      await refresh();
      await inspectPairing();
    }
  }catch(error){
    $("signIn").disabled=!config?.authEnabled;
    $("authHint").textContent=error.message;
    notice(error.message,true);
  }
}
for(const btn of document.querySelectorAll("[data-view]"))
  btn.addEventListener("click",()=>navigate(btn.dataset.view));
for(const btn of document.querySelectorAll("[data-go]"))
  btn.addEventListener("click",()=>navigate(btn.dataset.go));

$("workspaceSwitch").addEventListener("change",event=>{
  try{switchWorkspace(event.target.value);}
  catch(error){notice(error.message,true);}
});
$("joinTeamForm").addEventListener("submit",event=>{
  event.preventDefault();
  const button=event.currentTarget.querySelector("button");button.disabled=true;
  void (async()=>{
    const inviteToken=$("joinToken").value.trim();
    const result=await api("/v1/team/join",{method:"POST",body:{inviteToken}});
    $("joinToken").value="";
    notice("Team joined. Verify your role before requesting work.");
    workspaceId=result.workspaceId;
    sessionStorage.setItem("oagent_active_workspace",workspaceId);
    await refresh();navigate("team");
  })().catch(error=>notice(error.message,true)).finally(()=>{button.disabled=false;});
});
$("workspaceNameForm").addEventListener("submit",event=>{
  event.preventDefault();
  const button=event.currentTarget.querySelector("button");button.disabled=true;
  void api("/v1/team/settings",{method:"POST",
    body:{name:$("workspaceName").value.trim()}})
    .then(()=>{notice("Workspace name updated.");return refresh();})
    .catch(error=>notice(error.message,true))
    .finally(()=>{button.disabled=false;});
});
$("inviteTeamForm").addEventListener("submit",event=>{
  event.preventDefault();
  const button=event.currentTarget.querySelector("button");button.disabled=true;
  void api("/v1/team/invites",{method:"POST",
    body:{role:$("teamInviteRole").value}})
    .then(result=>{
      $("generatedInvite").value=result.inviteToken;
      $("inviteResult").hidden=false;
      notice("15-minute invitation created. Share it only with the intended teammate.");
    }).catch(error=>notice(error.message,true))
    .finally(()=>{button.disabled=false;});
});
$("copyTeamInvite").addEventListener("click",()=>{
  const value=$("generatedInvite").value;
  if(!/^oti_[A-Za-z0-9_-]{43}$/.test(value))return;
  void navigator.clipboard.writeText(value)
    .then(()=>notice("Invitation copied privately."))
    .catch(()=>notice("Copy unavailable. Select the invitation manually.",true));
});

$("signIn").addEventListener("click",()=>void authorize().catch(e=>notice(e.message,true)));
$("enableAlerts").addEventListener("click",()=>{
  const btn=$("enableAlerts");btn.disabled=true;
  void enableAlerts().catch(error=>notice(error.message,true)).finally(()=>{
    btn.disabled=false;
  });
});
if("serviceWorker" in navigator){
  navigator.serviceWorker.addEventListener("message",event=>{
    if(event.data?.type==="oagent-review-approvals"){
      navigate("approvals");void refresh();
    }
  });
}
$("signOut").addEventListener("click",()=>void signOut().catch(e=>notice(e.message,true)));
$("disableAlerts").addEventListener("click",()=>void disableAlerts().catch(e=>notice(e.message,true)));
$("refreshAudit").addEventListener("click",refresh);
$("exportAccount").addEventListener("click",()=>{
  const button=$("exportAccount");
  button.disabled=true;
  void exportMyAccount().catch(e=>notice(e.message,true))
    .finally(()=>{button.disabled=false;});
});
$("deleteAccount").addEventListener("click",()=>{
  $("deletePhrase").value="";$("ackLocalData").checked=false;
  $("deleteConfirm").disabled=true;
  $("deleteDialog").showModal();
});
const checkDelete=()=>{
  $("deleteConfirm").disabled=$("deletePhrase").value!=="DELETE_MY_OAGENT_WORKSPACE"||
    !$("ackLocalData").checked;
};
$("deletePhrase").addEventListener("input",checkDelete);
$("ackLocalData").addEventListener("change",checkDelete);
$("deleteCancel").addEventListener("click",()=>$("deleteDialog").close());
$("deleteConfirm").addEventListener("click",async()=>{
  const btn=$("deleteConfirm");btn.disabled=true;
  try{await deleteMyAccount();}
  catch(e){notice(e.message,true);checkDelete();}
});
$("menuButton").addEventListener("click",()=>$("sidebar").classList.toggle("open"));
$("refresh").addEventListener("click",refresh);
$("refreshApprovals").addEventListener("click",refresh);
$("deviceSelect").addEventListener("change",()=>{
  const selected=state.devices.find(x=>x.id===$("deviceSelect").value);
  $("cwd").value=selected?.workspace_root||"";
  updateProviderOptions();
});
$("runForm").addEventListener("submit",event=>
  void startSupervisedRun(event).catch(e=>notice(e.message,true)));
$("pairCancel").addEventListener("click",()=>{
  pendingPair=null;sessionStorage.removeItem("oagent_pending_pair");
  $("pairPanel").hidden=true;notice("Device pairing dismissed.");
});
$("pairApprove").addEventListener("click",async()=>{
  if(!pendingPair)return;
  const button=$("pairApprove");button.disabled=true;
  try{
    const verified=await api("/v1/devices/enrollments/inspect",{
      method:"POST",body:{pairingToken:pendingPair}});
    if(verified.fingerprint!==button.dataset.fingerprint)
      throw Error("The device public key changed. Generate a new pairing link.");
    const consent=await reviewExact({
      title:"Approve this exact device?",
      description:"Only approve a device that you personally own or administer.",
      detail:"Device: "+verified.name+"\nFingerprint: "+verified.fingerprint+
        "\n\nThis authorizes one signing key; it does not automatically grant agent tool access.",
      buttons:"confirm",confirmLabel:"Enroll this device",
    });
    if(!consent)return;
    await api("/v1/devices/enrollments/approve",{
      method:"POST",body:{pairingToken:pendingPair,
        expectedFingerprint:verified.fingerprint},
    });
    pendingPair=null;sessionStorage.removeItem("oagent_pending_pair");
    $("pairPanel").hidden=true;
    notice("Device approved. Its worker can now finish enrollment.");
    await refresh();
  }catch(error){notice(error.message,true);}
  finally{button.disabled=false;}
});
document.addEventListener("visibilitychange",()=>{if(!document.hidden)void refresh();});
setInterval(()=>{if(loggedIn())void refresh();},12000);
if("serviceWorker" in navigator){
  navigator.serviceWorker.register("/sw.js",{scope:"/"}).catch(()=>{
    // Installability is optional. Security-critical API calls work without SW.
  });
}
void bootstrap();
