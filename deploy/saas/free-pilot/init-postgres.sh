#!/bin/sh
set -eu
# Official postgres entrypoint runs this only for a fresh DB volume.
psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  -v ON_ERROR_STOP=1 \
  -v runtime="$OAGENT_RUNTIME_PASSWORD" \
  -v migrate="$OAGENT_MIGRATION_PASSWORD" \
  -v keycloak="$OAGENT_KEYCLOAK_DB_PASSWORD" <<'SQL'
SELECT format('CREATE ROLE oagent_runtime LOGIN NOSUPERUSER NOBYPASSRLS PASSWORD %L', :'runtime') \gexec
SELECT format('CREATE ROLE oagent_migrator LOGIN NOSUPERUSER NOBYPASSRLS PASSWORD %L', :'migrate') \gexec
SELECT format('CREATE ROLE oagent_keycloak LOGIN NOSUPERUSER NOBYPASSRLS PASSWORD %L', :'keycloak') \gexec
CREATE DATABASE oagent OWNER oagent_migrator;
CREATE DATABASE keycloak OWNER oagent_keycloak;
GRANT CONNECT ON DATABASE oagent TO oagent_runtime;
\connect oagent
GRANT USAGE ON SCHEMA public TO oagent_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE oagent_migrator IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO oagent_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE oagent_migrator IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO oagent_runtime;
SQL
