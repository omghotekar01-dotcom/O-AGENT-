"use strict";
(() => {
  const token = document.getElementById("token");
  const video = document.getElementById("video");
  const status = document.getElementById("state");
  const message = document.getElementById("message");
  const start = document.getElementById("start");
  const stop = document.getElementById("stop");
  const canvas = document.createElement("canvas");
  const context = canvas.getContext("2d");
  let media = null, lease = "", timer = null, busy = false, alive = false;
  const info = text => { message.textContent = text; };
  const authHeaders = () => ({Authorization: "Bearer " + token.value.trim()});
  async function request(path, method = "GET", headers = {}, body) {
    const response = await fetch(path, {
      method, headers: {...authHeaders(), ...headers}, body, cache: "no-store",
      credentials: "omit", redirect: "error",
    });
    if (!response.ok) throw Error("Backend returned HTTP " + response.status);
    return response.headers.get("content-type")?.includes("json")
      ? response.json() : null;
  }
  async function cleanup(revoke = true) {
    alive = false;
    if (timer) clearInterval(timer);
    timer = null;
    if (media) {
      for (const track of media.getTracks()) track.stop();
    }
    media = null; video.srcObject = null;
    if (revoke && lease) {
      try { await request("/api/screen/stop", "POST"); } catch {}
    }
    lease = ""; start.disabled = false; stop.disabled = true;
    status.textContent = "Not sharing";
    busy = false;
  }
  async function tick() {
    if (!alive || busy || !lease || !media) return;
    if (document.visibilityState !== "visible") return;
    const track = media.getVideoTracks()[0];
    if (!track || track.readyState !== "live") {
      await cleanup();
      info("The selected display has stopped sharing.");
      return;
    }
    if (!video.videoWidth || !video.videoHeight || !context) return;
    busy = true;
    try {
      const scale = Math.min(1, 900 / video.videoWidth, 540 / video.videoHeight);
      canvas.width = Math.max(1, Math.floor(video.videoWidth * scale));
      canvas.height = Math.max(1, Math.floor(video.videoHeight * scale));
      context.drawImage(video, 0, 0, canvas.width, canvas.height);
      const blob = await new Promise(resolve => canvas.toBlob(resolve, "image/jpeg", .49));
      if (!blob || blob.size > 160000) {
        info("Preview too large; adjust the shared area.");
        return;
      }
      await request("/api/screen/frame", "POST",
        {"Content-Type":"image/jpeg","X-OAGENT-Capture-Token": lease},blob);
      info("Sharing a consented view-only preview with the owner's phone.");
    } catch (err) {
      info("Screen upload stopped: " + err.message);
      await cleanup(false);
    } finally { busy = false; }
  }
  start.addEventListener("click", async () => {
    if (token.value.trim().length < 24) return info("Enter your existing owner token.");
    if (!navigator.mediaDevices?.getDisplayMedia) return info("Screen selection requires a modern HTTPS browser.");
    start.disabled = true;
    try {
      // The picker must originate directly from a user gesture. Do not
      // auto-start or silently request an additional display.
      media = await navigator.mediaDevices.getDisplayMedia({
        video: { frameRate: { ideal: 1, max: 2 } }, audio: false,
      });
      video.srcObject = media;
      media.getVideoTracks()[0]?.addEventListener("ended", () => {
        void cleanup(); info("Sharing ended using the browser's controls.");
      });
      await video.play();
      const entry = await request("/api/screen/start", "POST");
      lease = entry.captureToken;
      alive = true;
      stop.disabled = false;
      status.textContent = "Sharing selected display";
      info("Sharing started. Stop immediately whenever you need.");
      timer = setInterval(() => { void tick(); }, 1100);
      await tick();
    } catch (err) {
      info("Not sharing: " + err.message);
      await cleanup();
    }
  });
  stop.addEventListener("click", async () => {
    await cleanup();
    info("Sharing stopped. No frames are retained on the server.");
  });
  window.addEventListener("pagehide", () => {
    alive = false;
    for (const track of media?.getTracks() ?? []) track.stop();
    if (lease) {
      fetch("/api/screen/stop", {method:"POST",headers:authHeaders(),
        keepalive:true,credentials:"omit"}).catch(() => {});
    }
  });
})();