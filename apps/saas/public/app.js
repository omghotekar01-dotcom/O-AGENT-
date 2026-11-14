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
let state={devices:[],runs:[],approvals:[]};
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
  if(!["overview","approvals","runs","devices"].includes(view))return;
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
  if(!device.revoked_at){
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
  el.append(actions);node.append(el);
}
function renderApproval(node,approval){
  const el=entry(approval.kind==="tool"?"Agent tool permission":"Supervised agent task",
    approval.description, "pending");
  el.append(create("p","Device "+approval.device_id+" · Expires "+
    dateText(approval.expires_at),"entry-detail"));
  const actions=create("div",undefined,"entry-actions");
  const reviewButton=action(actions,"Review exact request",
    ()=>approveDialog(approval),"primary");
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
function reviewExact({title,description,detail,buttons="close"}){
  if(review)return Promise.resolve(null);
  $("reviewTitle").textContent=title;
  $("reviewDescription").textContent=description;
  $("reviewDetails").textContent=detail;
  $("reviewApprove").textContent=buttons==="revoke"?"Revoke device":"Approve once";
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
    detail:description,buttons:"revoke",
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
function render(){
  const {devices,runs,approvals}=state;
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
  const select=$("deviceSelect"),previous=select.value;
  select.replaceChildren();
  for(const device of devices.filter(fresh)){
    const option=create("option",device.name+" · "+device.id.slice(0,8));
    option.value=device.id;select.append(option);
  }
  if([...select.options].some(x=>x.value===previous))select.value=previous;
  updateProviderOptions();
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
    const [me,deviceData,runData,approvalData]=await Promise.all([
      api("/v1/me"),api("/v1/devices"),api("/v1/runs"),api("/v1/approvals"),
    ]);
    if(!me.tenantId)throw Error("Account identity was not verified.");
    state={
      devices:Array.isArray(deviceData.devices)?deviceData.devices:NONE,
      runs:Array.isArray(runData.runs)?runData.runs:NONE,
      approvals:Array.isArray(approvalData.approvals)?approvalData.approvals:NONE,
    };
    render();pillConnection(true);showAuth(true);
  }catch(error){
    pillConnection(false);
    // An unavailable provider must never be displayed as zero approved tasks.
    for(const id of ["statDevices","statRunning","statApprovals","statCompleted"])
      $(id).textContent="—";
    $("sidePending").textContent="!";
    notice("Unable to verify current workspace: "+error.message,true);
  }finally{refreshing=false;$("refresh").disabled=false;}
}
function disconnect(){
  accessToken=null;expiresAt=0;
  state={devices:[],runs:[],approvals:[]};
  showAuth(false);pillConnection(false);
}
async function bootstrap(){
  const hash=location.hash.startsWith("#pair=")?
    location.hash.slice("#pair=".length):null;
  if(hash){
    pendingPair=decodeURIComponent(hash);
    sessionStorage.setItem("oagent_pending_pair",pendingPair);
    history.replaceState(null,"",location.pathname+location.search);
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
$("signIn").addEventListener("click",()=>void authorize().catch(e=>notice(e.message,true)));
$("signOut").addEventListener("click",()=>{disconnect();notice("Signed out of this browser.");});
$("menuButton").addEventListener("click",()=>$("sidebar").classList.toggle("open"));
$("refresh").addEventListener("click",refresh);
$("refreshApprovals").addEventListener("click",refresh);
$("deviceSelect").addEventListener("change",updateProviderOptions);
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
      buttons:"revoke",
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
void bootstrap();
