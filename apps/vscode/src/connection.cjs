"use strict";

// VS Code is on the same machine as the O-AGENT Windows gateway, so HTTP
// loopback is safe and avoids an unnecessary Tailscale dependency.
// Non-loopback connections still MUST use HTTPS.
function parseBackendOrigin(value) {
  if (typeof value !== "string" || !value.trim())
    throw Error("Enter your O-AGENT backend URL, for example http://127.0.0.1:8787.");
  let url;
  try { url = new URL(value.trim()); }
  catch { throw Error("Enter a complete backend URL starting with http:// or https://."); }
  if (url.username || url.password || url.search || url.hash ||
      url.pathname !== "/")
    throw Error("Enter only the backend base address. Remove /api, login details, ?query and #fragment.");
  const local = ["127.0.0.1", "localhost", "[::1]"].includes(url.hostname.toLowerCase());
  if (url.protocol !== "https:" && !(url.protocol === "http:" && local))
    throw Error("Use HTTPS for remote servers. Plain HTTP is permitted only for local 127.0.0.1, localhost or [::1].");
  return url;
}

function explainHttpFailure(status, path) {
  const operation = path === "/api/workers/register" ? "enrollment" : "sync";
  switch (status) {
    case 400: return "The backend rejected the VS Code " + operation + " request (HTTP 400). Check that the backend is up to date.";
    case 401: return "Worker token rejected (HTTP 401). Configure the WORKER token from O-AGENT Windows settings, not your phone OPERATOR token or an AI API key.";
    case 403: return "Worker lacks permission (HTTP 403). Check your backend worker enrollment.";
    case 404: return "O-AGENT API route missing (HTTP 404). Restart the updated O-AGENT backend on your laptop.";
    case 409: return "Worker enrollment conflict (HTTP 409). Check that this editor is enrolled on the correct backend.";
    case 429: return "Backend is rate limiting requests (HTTP 429).";
    default:
      return status >= 500
        ? "O-AGENT backend/proxy returned HTTP " + status + ". Check laptop server and Tailscale Serve."
        : "O-AGENT backend request failed (HTTP " + status + ").";
  }
}

function explainFetchFailure(err, url) {
  const code = err?.cause?.code || err?.code;
  const name = err?.name;
  if (name === "TimeoutError" || name === "AbortError" ||
      code === "ETIMEDOUT") return "O-AGENT connection timed out. Check backend power/network and HTTPS routing.";
  if (code === "ECONNREFUSED")
    return "No backend is listening at " + url.origin + ". Start O-AGENT.cmd first.";
  if (code === "ENOTFOUND" || code === "EAI_AGAIN")
    return "Backend hostname cannot be resolved. Check your private Tailscale HTTPS address.";
  if (code === "DEPTH_ZERO_SELF_SIGNED_CERT" || code === "CERT_HAS_EXPIRED" ||
      code === "UNABLE_TO_VERIFY_LEAF_SIGNATURE")
    return "HTTPS certificate was rejected. Use a trusted private Tailscale HTTPS origin.";
  return "Cannot reach O-AGENT at " + url.origin +
    ". For VS Code on the same laptop, use http://127.0.0.1:8787 and the WORKER token.";
}

module.exports = { parseBackendOrigin, explainHttpFailure, explainFetchFailure };
