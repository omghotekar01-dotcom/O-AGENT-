-- Additive, signed-worker-only diagnostic for mobile session discovery.
-- No provider logs, paths, credentials, or error text are persisted here.
ALTER TABLE devices ADD COLUMN IF NOT EXISTS codex_session_health varchar(24)
  NOT NULL DEFAULT 'unknown'
  CHECK(codex_session_health IN
    ('unknown','available','no_saved_threads','missing_cli',
     'rpc_unavailable','scan_timeout','unavailable','disabled'));
ALTER TABLE devices ADD COLUMN IF NOT EXISTS codex_last_checked_at timestamptz;
