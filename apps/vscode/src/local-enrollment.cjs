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
    throw Error("Automatic setup may only connect to 127.0.0.1 on this laptop.");
  }
  if (typeof token !== "string" || token.length < 24 || token.length > 512 ||
      /[\u0000-\u001f]/.test(token)) {
    throw Error("Windows setup returned an invalid worker credential.");
  }
  return {url:origin.origin,token};
}

async function verifyLocalBackend(url,{fetchImpl = fetch}={}) {
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
  return true;
}
module.exports={readLocalEnrollment,verifyLocalBackend};
