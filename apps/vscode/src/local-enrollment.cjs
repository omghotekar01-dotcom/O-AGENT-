"use strict";
const { execFile } = require("node:child_process");
const { promisify } = require("node:util");
const { resolve } = require("node:path");
const { parseBackendOrigin } = require("./connection.cjs");

const execFileAsync = promisify(execFile);

async function readLocalEnrollment({
  platform = process.platform,
  remoteName = null,
  runner = execFileAsync,
} = {}) {
  if (platform !== "win32" || remoteName) {
    throw Error("Automatic setup works only in local VS Code on the same Windows laptop as O-AGENT. Use manual HTTPS connection for remote editors.");
  }
  const script = resolve(__dirname,"..","scripts","read-local-worker.ps1");
  let stdout;
  try {
    const result=await runner("powershell.exe",[
      "-NoLogo","-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass",
      "-File",script,
    ],{windowsHide:true,timeout:9000,maxBuffer:4096,encoding:"utf8"});
    stdout=result.stdout;
  } catch {
    throw Error("Cannot unlock O-AGENT Windows credentials. Start O-AGENT.cmd on this Windows account first. Your token has not been changed.");
  }
  let data;
  try { data=JSON.parse(stdout.trim()); }
  catch { throw Error("Local O-AGENT setup returned an invalid result. No credentials were saved."); }
  const token=data?.workerToken;
  let origin;
  try { origin=parseBackendOrigin(data?.origin); }
  catch { throw Error("Windows setup returned an invalid local backend address."); }
  if (origin.protocol !== "http:" || origin.hostname !== "127.0.0.1") {
    throw Error("Automatic local setup may only connect to 127.0.0.1 on this laptop.");
  }
  if (typeof token !== "string" || token.length < 24 || token.length > 512 ||
      /[\u0000-\u001f]/.test(token)) {
    throw Error("Windows setup returned an invalid worker credential.");
  }
  return {url:origin.origin,token};
}

async function verifyLocalBackend(url,{workerToken,fetchImpl = fetch}={}) {
  if (typeof workerToken !== "string" || workerToken.length < 24 ||
      /[\u0000-\u001f]/.test(workerToken)) {
    throw Error("A valid local Windows worker credential is required.");
  }
  const origin=parseBackendOrigin(url);
  if(origin.hostname!=="127.0.0.1" || origin.protocol!=="http:") {
    throw Error("Automatic setup only supports the loopback backend.");
  }
  let result;
  try {
    result=await fetchImpl(new URL("/health",origin),{
      method:"GET",redirect:"error",cache:"no-store",
      signal:AbortSignal.timeout(7000),
    });
  } catch {
    throw Error("O-AGENT is not responding on this laptop. Start O-AGENT.cmd and try Connect again.");
  }
  if (!result.ok) throw Error("Local O-AGENT backend returned HTTP " + result.status);
  const status=await result.json().catch(()=>({}));
  if(status.service!=="oagent-control-plane" || status.status!=="ok") {
    throw Error("The local port is not serving a verified O-AGENT backend.");
  }
  // Authenticate the WORKER token without registering a worker or changing
  // saved VS Code credentials. Never include secrets in errors.
  let probe;
  try {
    probe=await fetchImpl(new URL("/api/workers/credential-check",origin),{
      method:"GET",redirect:"error",cache:"no-store",
      headers:{authorization:"Bearer "+workerToken},
      signal:AbortSignal.timeout(7000),
    });
  } catch {
    throw Error("Could not verify the local worker credential. Restart O-AGENT.cmd and try again.");
  }
  if(probe.status===404) throw Error("O-AGENT backend needs the latest update. Restart O-AGENT.cmd with updated files.");
  if(probe.status===401 || probe.status===403)
    throw Error("Saved Windows WORKER token does not match the running backend. Restart O-AGENT.cmd with the same Windows account.");
  if(!probe.ok)throw Error("O-AGENT credential check failed (HTTP "+probe.status+").");
  const proof=await probe.json().catch(()=>({}));
  if(proof.authenticated!==true || proof.role!=="worker")
    throw Error("O-AGENT did not verify the saved worker credential.");
  return true;
}
module.exports={readLocalEnrollment,verifyLocalBackend};
