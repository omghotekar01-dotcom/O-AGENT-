-- Additive persisted Codex session snapshots sourced only from an enrolled,
-- Ed25519-authenticated worker. No access tokens or CLI credentials stored.
CREATE TABLE IF NOT EXISTS codex_sessions (
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  device_id uuid NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  session_id varchar(120) NOT NULL,
  cwd varchar(600) NOT NULL,
  title varchar(100) NOT NULL,
  preview varchar(240) NOT NULL DEFAULT '',
  source_kind varchar(12) NOT NULL CHECK (source_kind IN ('cli','vscode','unknown')),
  updated_at timestamptz NOT NULL,
  synced_at timestamptz NOT NULL DEFAULT now(),
  messages jsonb NOT NULL DEFAULT '[]'::jsonb,
  PRIMARY KEY (tenant_id,device_id,session_id)
);
CREATE INDEX IF NOT EXISTS codex_sessions_recent
  ON codex_sessions(tenant_id,updated_at DESC);
ALTER TABLE codex_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE codex_sessions FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON codex_sessions FOR ALL
  USING (tenant_id=nullif(current_setting('oagent.tenant_id',true),'')::uuid)
  WITH CHECK (tenant_id=nullif(current_setting('oagent.tenant_id',true),'')::uuid);
