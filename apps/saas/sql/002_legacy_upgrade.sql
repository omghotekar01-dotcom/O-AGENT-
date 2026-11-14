-- Forward-only compatibility with private pilots created before the
-- workspace-root and push-subscription schema additions.
-- Do not edit after the migration checksum is recorded.
ALTER TABLE devices ADD COLUMN IF NOT EXISTS workspace_root varchar(600);

CREATE TABLE IF NOT EXISTS push_subscriptions (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_id uuid NOT NULL REFERENCES tenants(id),
  endpoint_hash bytea NOT NULL UNIQUE,
  endpoint text NOT NULL,
  auth_key varchar(60) NOT NULL,
  p256dh_key varchar(140) NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS push_tenant_idx ON push_subscriptions(tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS push_tenant_endpoint_idx ON push_subscriptions(tenant_id,endpoint_hash);
ALTER TABLE push_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE push_subscriptions FORCE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
     AND tablename='push_subscriptions' AND policyname='tenant_scope') THEN
    CREATE POLICY tenant_scope ON push_subscriptions FOR ALL
      USING (tenant_id = nullif(current_setting('oagent.tenant_id',true),'')::uuid)
      WITH CHECK (tenant_id = nullif(current_setting('oagent.tenant_id',true),'')::uuid);
  END IF;
END $$;
