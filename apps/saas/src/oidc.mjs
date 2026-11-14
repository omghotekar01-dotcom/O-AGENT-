import {createRemoteJWKSet, jwtVerify} from "jose";

/** OIDC access-token verifier, no homemade JWT parsing or secret in browsers. */
export function createOidcVerifier(config, {jwksFactory=createRemoteJWKSet,
  verify=jwtVerify}={}) {
  const keys=jwksFactory(new URL(config.jwksUrl),{
    timeoutDuration:5000, cooldownDuration:30000,cacheMaxAge:300000,
  });
  return async function authenticate(header, requiredScope="oagent-read") {
    if(typeof header!=="string"||!/^Bearer [A-Za-z0-9._~-]{50,8000}$/.test(header))
      throw Object.assign(Error("Missing or invalid bearer token"),{status:401});
    let claims;
    try {
      const verified=await verify(header.slice(7),keys,{
        issuer:config.issuer,audience:config.audience,
        algorithms:["RS256","ES256","PS256"],clockTolerance:5,
      });
      claims=verified.payload;
    } catch {
      throw Object.assign(Error("Authentication failed"),{status:401});
    }
    const clientId=claims.azp || claims.client_id;
    if(typeof clientId!=="string" || !config.clientIds.includes(clientId) ||
       typeof claims.sub!=="string" || claims.sub.length<1 ||
       claims.sub.length>255 || claims.email_verified===false)
      throw Object.assign(Error("Access token client is not authorized"),{status:403});
    const scopes=new Set(typeof claims.scope==="string"?
      claims.scope.split(/\s+/).filter(Boolean):[]);
    if(requiredScope && !scopes.has(requiredScope))
      throw Object.assign(Error("Insufficient access token scope"),{status:403});
    return Object.freeze({issuer:config.issuer,subject:claims.sub,scopes,
      clientId,expiresAt:claims.exp});
  };
}
