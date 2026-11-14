-- O-AGENT SaaS v1. Run with a migration identity distinct from the runtime DB role.
-- All tenant data is FORCE RLS. Runtime MUST be non-superuser, not BYPASSRLS.
CREATE TABLE IF NOT EXISTS tenants (
  id uuid PRIMARY KEY, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS identities (
  issuer text NOT NULL, subject text NOT NULL, tenant_id uuid NOT NULL REFERENCES tenants(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (issuer, subject)
);
-- Authenticated pre-enrollment is unscoped until an owner claims the device via
-- an unguessable, expiring 256-bit token. Never expose this table to clients.
CREATE TABLE IF NOT EXISTS pending_devices (
  id uuid PRIMARY KEY, name varchar(80) NOT NULL, public_key bytea NOT NULL,
  token_hash bytea UNIQUE NOT NULL, source_hash bytea NOT NULL,
  approved_device_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS pending_devices_source_idx ON pending_devices(source_hash,created_at);

CREATE TABLE IF NOT EXISTS devices (
  id uuid PRIMARY KEY, tenant_id uuid NOT NULL REFERENCES tenants(id),
  name varchar(80) NOT NULL, capabilities jsonb NOT NULL DEFAULT '[]'::jsonb,
  workspace_root varchar(600),
  created_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz, revoked_at timestamptz
);
CREATE INDEX IF NOT EXISTS devices_tenant_idx ON devices(tenant_id,revoked_at);
-- Signed device auth index: lookup by random UUID before RLS context exists.
-- No HTTP endpoint lists or queries this table. Only verified signatures
-- can be elevated to scoped tenant transactions.
CREATE TABLE IF NOT EXISTS device_auth_keys (
  device_id uuid PRIMARY KEY REFERENCES devices(id) ON DELETE CASCADE,
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  public_key bytea NOT NULL,
  revoked_at timestamptz
);
CREATE TABLE IF NOT EXISTS device_replay_nonces (
  device_id uuid NOT NULL REFERENCES device_auth_keys(device_id) ON DELETE CASCADE,
  nonce varchar(100) NOT NULL, expires_at timestamptz NOT NULL,
  PRIMARY KEY (device_id,nonce)
);
CREATE INDEX IF NOT EXISTS device_replay_expiry ON device_replay_nonces(expires_at);
CREATE TABLE IF NOT EXISTS runs (
  id uuid PRIMARY KEY, tenant_id uuid NOT NULL REFERENCES tenants(id),
  device_id uuid NOT NULL REFERENCES devices(id),
  kind varchar(40) NOT NULL,
  mode varchar(30) NOT NULL,
  prompt text NOT NULL,
  cwd text NOT NULL DEFAULT '',
  session_id varchar(120),
  action_hash char(64) NOT NULL,
  request_key varchar(128) NOT NULL,
  status varchar(40) NOT NULL CHECK (status IN (
    'waiting_for_approval','queued','running','waiting_for_tool',
    'completed','failed','denied','cancelled','needs_recovery')),
  lease_token uuid, lease_expires_at timestamptz, lease_version bigint NOT NULL DEFAULT 0,
  result jsonb, error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id,request_key)
);
CREATE INDEX IF NOT EXISTS runs_claim_idx ON runs(device_id,status,created_at);
CREATE TABLE IF NOT EXISTS approvals (
  id uuid PRIMARY KEY, tenant_id uuid NOT NULL REFERENCES tenants(id),
  run_id uuid NOT NULL REFERENCES runs(id),
  device_id uuid NOT NULL REFERENCES devices(id),
  kind varchar(16) NOT NULL CHECK (kind IN ('run','tool')),
  description text NOT NULL, action_hash char(64) NOT NULL,
  status varchar(16) NOT NULL CHECK (status IN ('pending','approved','denied')),
  requested_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL, decided_at timestamptz, decided_by text,
  UNIQUE (tenant_id,run_id,kind,action_hash)
);
CREATE INDEX IF NOT EXISTS approvals_pending ON approvals(tenant_id,status,expires_at);
CREATE TABLE IF NOT EXISTS run_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  run_id uuid NOT NULL REFERENCES runs(id),
  kind varchar(24) NOT NULL, text varchar(2200) NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS run_events_read ON run_events(tenant_id,run_id,id);
ALTER TABLE run_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE run_events FORCE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS audit_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  actor varchar(160) NOT NULL, action varchar(100) NOT NULL,
  target_id uuid, created_at timestamptz NOT NULL DEFAULT now(),
  detail jsonb NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX IF NOT EXISTS audit_tenant_seq ON audit_events(tenant_id,id);

ALTER TABLE devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE devices FORCE ROW LEVEL SECURITY;
ALTER TABLE runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE runs FORCE ROW LEVEL SECURITY;
ALTER TABLE approvals ENABLE ROW LEVEL SECURITY;
ALTER TABLE approvals FORCE ROW LEVEL SECURITY;
ALTER TABLE audit_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_events FORCE ROW LEVEL SECURITY;

-- No policy with unrestricted USING(true). tenant context is a transaction-local
-- setting from a verified OIDC identity or a verified Ed25519 device signature.
DO $$
DECLARE tbl text;
BEGIN
  FOREACH tbl IN ARRAY ARRAY['devices','runs','approvals','run_events','audit_events'] LOOP
    IF NOT EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='public'
       AND tablename=tbl AND policyname='tenant_scope') THEN
      EXECUTE format(
        'CREATE POLICY tenant_scope ON %I FOR ALL USING (tenant_id = nullif(current_setting(''oagent.tenant_id'',true),'''')::uuid) WITH CHECK (tenant_id = nullif(current_setting(''oagent.tenant_id'',true),'''')::uuid)',tbl);
    END IF;
  END LOOP;
END $$;
