import {readSaasConfig} from "./config.mjs";
import {createPool,migrate} from "./store.mjs";
const config=readSaasConfig(process.env);
if(!process.env.OAGENT_MIGRATION_DATABASE_URL)
  throw Error("OAGENT_MIGRATION_DATABASE_URL is required for schema migration; use a separate admin identity");
const pool=createPool({...config,databaseUrl:process.env.OAGENT_MIGRATION_DATABASE_URL});
try {await migrate(pool);console.log("O-AGENT SaaS schema migration complete");}
finally {await pool.end();}
