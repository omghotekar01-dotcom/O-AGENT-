// This worker enables installable mobile access without paid app stores.
// Important: never cache tokens, approval data, sessions, prompts or API responses.
self.addEventListener("install",event=>event.waitUntil(self.skipWaiting()));
self.addEventListener("activate",event=>event.waitUntil(self.clients.claim()));
// Intentionally no fetch handler: every authenticated request must go to the
// real backend, and offline data must NEVER masquerade as a current approval.
