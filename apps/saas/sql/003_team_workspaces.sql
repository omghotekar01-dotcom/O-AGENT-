-- Additive team workspace foundation. Do not edit this migration once applied.
-- Each signed-in identity retains its own private tenant; explicit workspace
-- selection requires membership in the selected tenant. Never trust an
-- arbitrary tenant ID as authorization.
ALTER TABLE tenants ADD COLUMN IF NOT EXISTS display_name varchar(80);

CREATE TABLE IF NOT EXISTS tenant_members (
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  issuer text NOT NULL,
  subject text NOT NULL,
  role varchar(16) NOT NULL CHECK (role IN ('owner','operator','viewer')),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id,issuer,subject)
);
CREATE INDEX IF NOT EXISTS tenant_members_identity_idx
  ON tenant_members(issuer,subject,tenant_id);
INSERT INTO tenant_members(tenant_id,issuer,subject,role)
  SELECT tenant_id,issuer,subject,'owner' FROM identities
  ON CONFLICT DO NOTHING;

ALTER TABLE tenant_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_members FORCE ROW LEVEL SECURITY;
-- A verified identity can list its own workspace memberships while the
-- currently selected tenant can list its teammates.
CREATE POLICY team_members_read ON tenant_members FOR SELECT USING (
  tenant_id=nullif(current_setting('oagent.tenant_id',true),'')::uuid
  OR (issuer=current_setting('oagent.identity_issuer',true)
      AND subject=current_setting('oagent.identity_subject',true))
);
CREATE POLICY team_members_insert ON tenant_members FOR INSERT WITH CHECK (
  tenant_id=nullif(current_setting('oagent.tenant_id',true),'')::uuid
);
CREATE POLICY team_members_update ON tenant_members FOR UPDATE
  USING (tenant_id=nullif(current_setting('oagent.tenant_id',true),'')::uuid)
  WITH CHECK (tenant_id=nullif(current_setting('oagent.tenant_id',true),'')::uuid);
CREATE POLICY team_members_delete ON tenant_members FOR DELETE
  USING (tenant_id=nullif(current_setting('oagent.tenant_id',true),'')::uuid);

-- Before redemption an invite has no authenticated tenant. This table is
-- intentionally unscoped like pending_devices: random 256-bit token hashes
-- only, no invite plaintext, and no generic HTTP query endpoint.
CREATE TABLE IF NOT EXISTS pending_team_invites (
  id uuid PRIMARY KEY,
  tenant_id uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  token_hash bytea NOT NULL UNIQUE,
  role varchar(16) NOT NULL CHECK(role IN ('operator','viewer')),
  created_by varchar(160) NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  redeemed_at timestamptz,
  redeemed_by varchar(160)
);
CREATE INDEX IF NOT EXISTS pending_team_invites_expiry_idx
  ON pending_team_invites(expires_at) WHERE redeemed_at IS NULL;
