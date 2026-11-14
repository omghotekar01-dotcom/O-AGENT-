// No fetch handler, cache or token storage. Real approvals must be online.
self.addEventListener("install",event=>event.waitUntil(self.skipWaiting()));
self.addEventListener("activate",event=>event.waitUntil(self.clients.claim()));
self.addEventListener("push",event=>{
  let message={};
  try{message=event.data?.json()||{};}catch{}
  if(message.type!=="approval")return;
  // Generic notification protects code, paths and sensitive prompt content.
  event.waitUntil(self.registration.showNotification("O-AGENT approval needed",{
    body:"Open your command center to review a real agent request",
    icon:"/icon.svg",badge:"/icon.svg",tag:"oagent-approval",renotify:true,
    data:{url:"/?view=approvals"},
  }));
});
self.addEventListener("notificationclick",event=>{
  event.notification.close();
  const page=new URL("/?view=approvals",self.location.origin).href;
  event.waitUntil((async()=>{
    const windows=await self.clients.matchAll({type:"window",includeUncontrolled:true});
    for(const client of windows){
      if(new URL(client.url).origin===self.location.origin){
        await client.focus();
        client.postMessage({type:"oagent-review-approvals"});
        return;
      }
    }
    await self.clients.openWindow(page);
  })());
});
