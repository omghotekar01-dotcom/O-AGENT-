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
  let maxDimension = 1140, jpegQuality = .54, lastUploadMs = 0;
  let nextPublishAt = 0, consecutiveThrottles = 0, transientFailures = 0;
  const info = text => { message.textContent = text; };
  const authHeaders = () => ({Authorization: "Bearer " + token.value.trim()});
  async function request(path, method = "GET", headers = {}, body) {
    const response = await fetch(path, {
      method, headers: {...authHeaders(), ...headers}, body, cache: "no-store",
      credentials: "omit", redirect: "error",
    });
    if (!response.ok) {
      const error = new Error("Backend returned HTTP " + response.status);
      error.status = response.status;
      const retry = Number(response.headers.get("retry-after"));
      error.retryAfterMs = Number.isFinite(retry) && retry > 0
        ? Math.min(5000, retry * 1000) : null;
      throw error;
    }
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
    if (!alive || busy || !lease || !media || performance.now() < nextPublishAt) return;
    // Screen capture permission remains browser-controlled and visible to the
    // laptop user. Continue publishing while the picker page is backgrounded,
    // e.g. when the user switches to the VS Code window they chose to share.
    // Browsers can still throttle background timers; no zero-latency guarantee.
    const track = media.getVideoTracks()[0];
    if (!track || track.readyState !== "live") {
      await cleanup();
      info("The selected display has stopped sharing.");
      return;
    }
    if (!video.videoWidth || !video.videoHeight || !context) return;
    busy = true;
    try {
      const scale = Math.min(1, maxDimension / video.videoWidth,
        720 / video.videoHeight);
      canvas.width = Math.max(1, Math.floor(video.videoWidth * scale));
      canvas.height = Math.max(1, Math.floor(video.videoHeight * scale));
      context.drawImage(video, 0, 0, canvas.width, canvas.height);
      let blob = await new Promise(resolve => canvas.toBlob(resolve, "image/jpeg", jpegQuality));
      if (blob && blob.size > 230000) {
        // Large noisy frames must not kill the whole screen-sharing session.
        // Drop the size and quality, then retry on the next capture interval.
        maxDimension = Math.max(680, Math.round(maxDimension * .88));
        jpegQuality = Math.max(.39, jpegQuality - .04);
        return;
      }
      if (!blob) { info("Could not encode shared screen. Check browser permissions.");return; }
      const sentAt = performance.now();
      await request("/api/screen/frame", "POST",
        {"Content-Type":"image/jpeg","X-OAGENT-Capture-Token": lease},blob);
      lastUploadMs = performance.now() - sentAt;
      consecutiveThrottles = 0;
      transientFailures = 0;
      nextPublishAt = performance.now() + 260;
      // Adapt to connection RTT rather than accumulating stale frames.
      if (lastUploadMs > 850) {
        maxDimension = Math.max(680, Math.round(maxDimension * .92));
        jpegQuality = Math.max(.40, jpegQuality - .02);
      } else if(lastUploadMs < 300 && blob.size < 125000) {
        maxDimension = Math.min(1280, maxDimension + 25);
        jpegQuality = Math.min(.65, jpegQuality + .01);
      }
      info("Sharing selected screen · adaptive preview · upload " +
        Math.round(lastUploadMs) + " ms");
    } catch (err) {
      if (err.status === 429) {
        // HTTP 429 is a temporary capture-rate throttle, not revoked
        // consent. Keep the same display track/lease alive; do not prompt
        // the user to repeat screen selection or expose their token.
        consecutiveThrottles += 1;
        const delay = err.retryAfterMs ??
          Math.min(4000, 700 * (2 ** Math.min(3, consecutiveThrottles - 1)));
        nextPublishAt = performance.now() + delay;
        info("Capture briefly throttled (HTTP 429). Retrying automatically in " +
          Math.ceil(delay / 1000) + "s. Screen permission remains active.");
        return;
      }
      if (err.status === 502 || err.status === 503 ||
          err.status === 504 || err.name === "TypeError") {
        transientFailures += 1;
        const delay = Math.min(5000, 400 * (2 ** Math.min(4, transientFailures - 1)));
        nextPublishAt = performance.now() + delay;
        info("Connection interrupted (" + err.message +
          "). Retrying automatically; remote input will pause if frames go stale.");
        return;
      }
      info("Screen upload stopped: " + err.message +
        ". Check the server/token, then select a screen again.");
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
        video: { frameRate: { ideal: 6, max: 8 } }, audio: false,
      });
      video.srcObject = media;
      media.getVideoTracks()[0]?.addEventListener("ended", () => {
        void cleanup(); info("Sharing ended using the browser's controls.");
      });
      await video.play();
      const selected = media.getVideoTracks()[0]?.getSettings?.() ?? {};
      const entry = await request("/api/screen/start", "POST",
        {"Content-Type":"application/json"}, JSON.stringify({
          displaySurface: ["monitor","window","browser"].includes(selected.displaySurface)
            ? selected.displaySurface : "unknown",
          sourceWidth: video.videoWidth,
          sourceHeight: video.videoHeight,
        }));
      lease = entry.captureToken;
      nextPublishAt = 0;
      consecutiveThrottles = 0;
      transientFailures = 0;
      alive = true;
      stop.disabled = false;
      status.textContent = "Sharing selected display";
      info("Sharing started. Stop immediately whenever you need.");
      timer = setInterval(() => { void tick(); }, 250);
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