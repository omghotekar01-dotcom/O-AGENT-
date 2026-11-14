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
  const issuer = absolute(required(env,"OAGENT_OIDC_ISSUER"),"OAGENT_OIDC_ISSUER");
  const jwks = absolute(required(env,"OAGENT_OIDC_JWKS_URL"),"OAGENT_OIDC_JWKS_URL");
  const db = new URL(required(env,"DATABASE_URL"));
  if (!["postgres:","postgresql:"].includes(db.protocol) || !db.hostname)
    throw Error("DATABASE_URL must be a PostgreSQL connection URL");
  // A database server certificate must be verified. Never allow sslmode=disable
  // in a public release; local CI uses a separate isolated test config.
  if (env.NODE_ENV !== "test" &&
      ["disable","allow","prefer","no-verify"].includes(db.searchParams.get("sslmode")))
    throw Error("Insecure DATABASE_URL sslmode rejected");
  const clientIds = required(env,"OAGENT_OIDC_CLIENT_IDS").split(",").map(s=>s.trim()).filter(Boolean);
  if (!clientIds.length || clientIds.some(s=>s.length>250)) throw Error("Invalid OIDC client allowlist");
  const audience = required(env,"OAGENT_OIDC_AUDIENCE");
  if (audience.length > 500) throw Error("OIDC audience too long");
  const port = Number(env.PORT || 8790);
  if (!Number.isSafeInteger(port) || port<1 || port>65535) throw Error("Invalid PORT");
  return Object.freeze({
    publicOrigin:publicUrl.origin, issuer:issuer.href, jwksUrl:jwks.href,
    audience, clientIds, databaseUrl:db.href,
    host:env.HOST || "127.0.0.1", port,
    mode:env.NODE_ENV || "production",
  });
}
