const $ = id => document.getElementById(id);
let token = sessionStorage.getItem("oagent_token") || "";
let busy = false;
function notice(text) { $("notice").textContent = text; }
async function api(path, opts = {}) {
  const r = await fetch(path, { ...opts, headers: { authorization: "Bearer " + token, "content-type": "application/json", ...(opts.headers || {}) } });
  const data = await r.json();
  if (!r.ok) throw new Error(data.error || "Request failed");
  return data;
}
function element(tag, text, cls) {
  const n = document.createElement(tag);
  if (text !== undefined) n.textContent = String(text);
  if (cls) n.className = cls;
  return n;
}
function empty(target, text) { target.replaceChildren(element("p", text, "hint")); }
function renderItem(title, details, state) {
  const item = element("article", undefined, "item");
  item.append(element("strong", title), element("div", details, "meta"));
  if (state) item.append(element("span", state, "pill"));
  return item;
}
function addAction(item, title, action) {
  const row = item.querySelector(".actions") || element("div", undefined, "actions");
  const button = element("button", title, "secondary");
  button.type = "button";
  button.addEventListener("click", async () => {
    button.disabled = true;
    try { await action(); await refresh(); } catch(e) { notice(e.message); } finally { button.disabled = false; }
  });
  row.append(button);
  if (!row.parentNode) item.append(row);
}
function render(data, events) {
  $("machines").textContent = data.workers.length;
  $("online").textContent = data.workers.filter(w => w.status === "online").length;
  $("running").textContent = data.tasks.filter(t => t.status === "running").length;
  $("approvals").textContent = data.tasks.filter(t => t.status === "waiting_for_approval").length;
  const workers = $("workerList");
  workers.replaceChildren();
  const select = $("workerSelect");
  const current = select.value;
  select.replaceChildren();
  for (const worker of data.workers) {
    workers.append(renderItem(worker.name, worker.id + " · last seen " + new Date(worker.lastSeenAt).toLocaleString(), worker.status));
    if (worker.status === "online") {
      const option = element("option", worker.name + " (" + worker.id + ")");
      option.value = worker.id;
      select.append(option);
    }
  }
  if (!data.workers.length) empty(workers, "No registered machines. Start the gateway to connect one.");
  if (current && [...select.options].some(o => o.value === current)) select.value = current;
  $("taskForm").querySelector("button").disabled = select.options.length === 0;
  const tasks = $("taskList");
  tasks.replaceChildren();
  for (const task of data.tasks.slice(0, 30)) {
    const item = renderItem(task.kind.replaceAll("_", " "), task.workerId + " · " + new Date(task.createdAt).toLocaleString(), task.status);
    if (task.status === "waiting_for_approval") {
      addAction(item, "Approve", () => api("/api/tasks/" + task.id + "/decision", { method: "POST", body: JSON.stringify({ approve: true }) }));
      addAction(item, "Reject", () => api("/api/tasks/" + task.id + "/decision", { method: "POST", body: JSON.stringify({ approve: false }) }));
    } else if (task.status === "queued") {
      addAction(item, "Cancel", () => api("/api/tasks/" + task.id + "/cancel", { method: "POST" }));
    }
    if (task.result) item.append(element("pre", JSON.stringify(task.result, null, 2), "result"));
    if (task.error) item.append(element("p", task.error, "meta"));
    tasks.append(item);
  }
  if (!data.tasks.length) empty(tasks, "No tasks yet. Submit one to a connected worker.");
  const eventPanel = $("eventList");
  eventPanel.replaceChildren();
  for (const ev of events.events.slice(-15).reverse()) eventPanel.append(renderItem(ev.type, new Date(ev.at).toLocaleString() + " · " + (ev.taskId || ev.workerId || ""), null));
  if (!events.events.length) empty(eventPanel, "No events recorded.");
}
async function refresh() {
  if (!token || busy || document.hidden) return;
  busy = true;
  try {
    const [data, events] = await Promise.all([api("/api/state"), api("/api/events")]);
    render(data, events);
    $("workspace").hidden = false;
    $("authPanel").hidden = true;
    notice("");
  } catch (err) { notice("Connection error: " + err.message); }
  finally { busy = false; }
}
$("authForm").addEventListener("submit", async event => {
  event.preventDefault();
  token = $("token").value.trim();
  sessionStorage.setItem("oagent_token", token);
  await refresh();
});
$("taskForm").addEventListener("submit", async event => {
  event.preventDefault();
  try {
    await api("/api/tasks", { method: "POST", headers: { "idempotency-key": crypto.randomUUID() }, body: JSON.stringify({ workerId: $("workerSelect").value, kind: $("kind").value }) });
    await refresh();
  } catch(e) { notice(e.message); }
});
$("refresh").addEventListener("click", refresh);
$("disconnect").addEventListener("click", () => { sessionStorage.removeItem("oagent_token"); token = ""; $("workspace").hidden = true; $("authPanel").hidden = false; $("token").value = ""; });
setInterval(refresh, 5000);
if (token) refresh();
