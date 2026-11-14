// This service deliberately does not accept legacy global operator/worker tokens.
const required = (env, name) => {
  const value = env[name];
  if (typeof value !== "string" || !value.trim()) throw Error(name + " is required");
  return value.trim();
};
const absolute = (value, name, {httpLoopback = false} = {}) => {
  let url;
  try { url = new URL(value); } catch { throw Error(name + " must be a valid URL"); }
  const loopback = ["localhost","127.0.0.1","[::1]"].includes(url.hostname);
  if ((url.protocol !== "https:" && !(httpLoopback && loopback && url.protocol === "http:")) ||
      url.username || url.password || url.search || url.hash)
    throw Error(name + " must be a secure origin or issuer URL");
  return url;
};
export function readSaasConfig(env = process.env) {
  const publicUrl = absolute(required(env,"OAGENT_SAAS_ORIGIN"),
    "OAGENT_SAAS_ORIGIN", {httpLoopback:env.NODE_ENV==="test"});
  if (publicUrl.pathname !== "/" || publicUrl.search || publicUrl.hash)
    throw Error("OAGENT_SAAS_ORIGIN must contain no path");
  // Issuer comparison is byte-exact in OIDC. URL() may append a slash, so
  // validate the URL but preserve the identity provider's advertised string.
  const issuerValue=required(env,"OAGENT_OIDC_ISSUER");
  absolute(issuerValue,"OAGENT_OIDC_ISSUER");
  // Explicit personal Tailnet-only mode; NEVER selected in commercial deployments.
  const localPilot=env.OAGENT_LOCAL_PILOT==="1";
  if(localPilot && (!/\\.ts\\.net$/i.test(publicUrl.hostname) || env.NODE_ENV==="test"))
    throw Error("Private pilot requires a non-test HTTPS Tailscale .ts.net origin");
  const requestedJwks=required(env,"OAGENT_OIDC_JWKS_URL");
  const internalKeycloak="http://identity:8080/auth/realms/oagent/protocol/openid-connect/certs";
  const jwksValue=localPilot&&requestedJwks===internalKeycloak
    ?requestedJwks:absolute(requestedJwks,"OAGENT_OIDC_JWKS_URL").href;
  const db = new URL(required(env,"DATABASE_URL"));
  if (!["postgres:","postgresql:"].includes(db.protocol) || !db.hostname)
    throw Error("DATABASE_URL must be a PostgreSQL connection URL");
  // PostgreSQL TLS hostname verification is mandatory outside isolated tests.
  const privatePilotDb=localPilot&&db.hostname==="db"&&
    db.searchParams.get("sslmode")==="disable";
  if (env.NODE_ENV !== "test" && !privatePilotDb &&
      db.searchParams.get("sslmode")!=="verify-full")
    throw Error("Production DATABASE_URL must use sslmode=verify-full");
  const clientIds = required(env,"OAGENT_OIDC_CLIENT_IDS").split(",").map(s=>s.trim()).filter(Boolean);
  if (!clientIds.length || clientIds.some(s=>s.length>250)) throw Error("Invalid OIDC client allowlist");
  let webAuth=null;
  const webKeys=["OAGENT_OIDC_WEB_CLIENT_ID","OAGENT_OIDC_AUTHORIZE_URL",
    "OAGENT_OIDC_TOKEN_URL"];
  if(webKeys.every(k=>typeof env[k]==="string"&&env[k].trim())){
    const clientId=required(env,"OAGENT_OIDC_WEB_CLIENT_ID");
    if(!clientIds.includes(clientId))
      throw Error("OIDC web client must be present in OIDC client allowlist");
    const authorize=absolute(required(env,"OAGENT_OIDC_AUTHORIZE_URL"),
      "OAGENT_OIDC_AUTHORIZE_URL");
    const token=absolute(required(env,"OAGENT_OIDC_TOKEN_URL"),
      "OAGENT_OIDC_TOKEN_URL");
    webAuth={clientId,authorizationEndpoint:authorize.href,
      tokenEndpoint:token.href,redirectUri:publicUrl.origin+"/"};
  } else if(webKeys.some(k=>typeof env[k]==="string"&&env[k].trim())){
    throw Error("Configure all three OIDC web login settings, or none");
  }
  const audience = required(env,"OAGENT_OIDC_AUDIENCE");
  if (audience.length > 500) throw Error("OIDC audience too long");
  const port = Number(env.PORT || 8790);
  if (!Number.isSafeInteger(port) || port<1 || port>65535) throw Error("Invalid PORT");
  return Object.freeze({
    publicOrigin:publicUrl.origin, issuer:issuerValue, jwksUrl:jwksValue,
    audience, clientIds, webAuth, databaseUrl:db.href, localPilot,
    host:env.HOST || "127.0.0.1", port,
    mode:env.NODE_ENV || "production",
  });
}
