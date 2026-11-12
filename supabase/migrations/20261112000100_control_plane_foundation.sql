-- OMIO AGENT HQ initial control-plane schema.
-- All operational writes go through the authenticated control-plane API.
-- No provider secrets are stored in these tables.

create extension if not exists pgcrypto;

create type public.run_state as enum (
  'draft', 'ready', 'queued', 'starting', 'running',
  'waiting_for_input', 'waiting_for_approval', 'waiting_for_device',
  'paused', 'recovering', 'completed', 'failed', 'cancelled'
);

create type public.device_platform as enum ('android', 'windows', 'linux', 'macos', 'web');
create type public.device_state as enum ('pending', 'online', 'offline', 'degraded', 'revoked');
create type public.connection_state as enum (
  'not_connected', 'authorizing', 'connected', 'degraded', 'expired', 'revoked', 'error', 'unsupported'
);
create type public.agent_kind as enum ('omio_managed', 'provider_managed', 'workspace_worker');
create type public.approval_state as enum ('pending', 'approved', 'rejected', 'expired', 'cancelled');

create table public.workspaces (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 120),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index workspaces_owner_idx on public.workspaces(owner_user_id);

create table public.projects (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 120),
  slug text not null check (slug ~ '^[a-z0-9]+([a-z0-9-]*[a-z0-9])?$'),
  description text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (workspace_id, slug),
  unique (id, workspace_id)
);

create index projects_workspace_idx on public.projects(workspace_id);

create table public.devices (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 120),
  platform public.device_platform not null,
  state public.device_state not null default 'pending',
  public_key_fingerprint text not null,
  attestation_level text,
  last_seen_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  unique (workspace_id, public_key_fingerprint),
  unique (id, workspace_id)
);

create index devices_workspace_state_idx on public.devices(workspace_id, state);

create table public.provider_connections (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  project_id uuid,
  provider_id text not null check (provider_id ~ '^[a-z0-9][a-z0-9._-]{1,63}$'),
  display_name text not null,
  auth_method text not null check (auth_method in ('oauth', 'api_key', 'device_code', 'local_sdk', 'managed_session')),
  state public.connection_state not null default 'not_connected',
  capability_manifest jsonb not null default '{}'::jsonb,
  last_health_check_at timestamptz,
  last_health_check_error_code text,
  lifecycle jsonb not null default '{"beta":false,"preview":false,"deprecated":false}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (project_id, workspace_id) references public.projects(id, workspace_id) on delete restrict,
  unique (id, workspace_id)
);

-- Secret handles live in a non-exposed schema. Secret values themselves live in KMS.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to service_role;
create table private.provider_connection_credentials (
  provider_connection_id uuid primary key references public.provider_connections(id) on delete cascade,
  secret_ref text not null,
  key_version text not null,
  rotated_at timestamptz,
  updated_at timestamptz not null default now()
);
alter table private.provider_connection_credentials enable row level security;
revoke all on private.provider_connection_credentials from public, anon, authenticated;
grant select, insert, update, delete on private.provider_connection_credentials to service_role;

create index provider_connections_workspace_idx on public.provider_connections(workspace_id, provider_id);

create table public.agents (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  project_id uuid,
  provider_connection_id uuid,
  name text not null check (char_length(name) between 1 and 120),
  kind public.agent_kind not null,
  status text not null default 'idle' check (status in ('idle', 'ready', 'busy', 'waiting', 'paused', 'error', 'archived')),
  definition_version integer not null default 1 check (definition_version > 0),
  model_id text,
  configuration jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (project_id, workspace_id) references public.projects(id, workspace_id) on delete restrict,
  foreign key (provider_connection_id, workspace_id) references public.provider_connections(id, workspace_id) on delete restrict,
  unique (id, workspace_id)
);

create index agents_workspace_status_idx on public.agents(workspace_id, status);

create table public.agent_runs (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  project_id uuid,
  agent_id uuid not null,
  state public.run_state not null default 'draft',
  version bigint not null default 1 check (version > 0),
  idempotency_key text not null check (char_length(idempotency_key) between 16 and 200),
  external_session_id text,
  worker_device_id uuid,
  lease_fencing_token bigint not null default 0,
  budget jsonb not null default '{}'::jsonb,
  failure_code text,
  started_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (project_id, workspace_id) references public.projects(id, workspace_id) on delete restrict,
  foreign key (agent_id, workspace_id) references public.agents(id, workspace_id) on delete cascade,
  foreign key (worker_device_id, workspace_id) references public.devices(id, workspace_id) on delete restrict,
  unique (workspace_id, idempotency_key),
  unique (id, workspace_id)
);

create index agent_runs_workspace_state_idx on public.agent_runs(workspace_id, state, updated_at desc);
create index agent_runs_agent_created_idx on public.agent_runs(agent_id, created_at desc);

create table public.approvals (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  run_id uuid not null,
  command_id uuid not null,
  state public.approval_state not null default 'pending',
  action_type text not null,
  target text not null,
  canonical_arguments_sha256 char(64) not null check (canonical_arguments_sha256 ~ '^[0-9a-f]{64}$'),
  risk_level text not null check (risk_level in ('low', 'medium', 'high', 'critical')),
  requested_by uuid references auth.users(id) on delete set null,
  decided_by uuid references auth.users(id) on delete set null,
  decision_reason text,
  expires_at timestamptz not null,
  decided_at timestamptz,
  created_at timestamptz not null default now(),
  foreign key (run_id, workspace_id) references public.agent_runs(id, workspace_id) on delete cascade,
  unique (command_id)
);

create index approvals_workspace_pending_idx on public.approvals(workspace_id, state, expires_at);

create table public.agent_events (
  sequence bigint generated always as identity primary key,
  event_id uuid not null unique default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  project_id uuid,
  agent_id uuid,
  run_id uuid,
  actor_type text not null check (actor_type in ('user', 'agent', 'provider', 'worker', 'system')),
  actor_id text,
  source text not null,
  event_type text not null,
  schema_version integer not null default 1,
  trace_id text,
  target text,
  argument_sha256 char(64),
  policy_decision text,
  approval_id uuid references public.approvals(id) on delete set null,
  result_status text,
  error_code text,
  artifact_refs jsonb not null default '[]'::jsonb,
  payload_redacted jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null,
  received_at timestamptz not null default now(),
  foreign key (project_id, workspace_id) references public.projects(id, workspace_id) on delete restrict,
  foreign key (agent_id, workspace_id) references public.agents(id, workspace_id) on delete restrict,
  foreign key (run_id, workspace_id) references public.agent_runs(id, workspace_id) on delete cascade,
  unique (workspace_id, sequence)
);

create index agent_events_workspace_cursor_idx on public.agent_events(workspace_id, sequence);
create index agent_events_run_idx on public.agent_events(run_id, sequence);

create table public.event_outbox (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.agent_events(event_id) on delete cascade,
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  destination text not null,
  attempts integer not null default 0 check (attempts >= 0),
  available_at timestamptz not null default now(),
  published_at timestamptz,
  last_error_code text,
  created_at timestamptz not null default now(),
  unique (event_id, destination)
);

create index event_outbox_pending_idx on public.event_outbox(available_at) where published_at is null;

create table public.artifacts (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  project_id uuid,
  run_id uuid,
  storage_bucket text not null,
  storage_object_key text not null,
  content_type text not null,
  byte_size bigint not null check (byte_size >= 0),
  sha256 char(64) not null check (sha256 ~ '^[0-9a-f]{64}$'),
  sensitivity text not null default 'internal' check (sensitivity in ('public', 'internal', 'confidential', 'restricted')),
  redaction_status text not null default 'pending' check (redaction_status in ('pending', 'complete', 'blocked')),
  created_at timestamptz not null default now(),
  foreign key (project_id, workspace_id) references public.projects(id, workspace_id) on delete restrict,
  foreign key (run_id, workspace_id) references public.agent_runs(id, workspace_id) on delete restrict,
  unique (storage_bucket, storage_object_key)
);

create index artifacts_workspace_created_idx on public.artifacts(workspace_id, created_at desc);

-- RLS is enabled on every table in the exposed public schema.
alter table public.workspaces enable row level security;
alter table public.projects enable row level security;
alter table public.devices enable row level security;
alter table public.provider_connections enable row level security;
alter table public.agents enable row level security;
alter table public.agent_runs enable row level security;
alter table public.approvals enable row level security;
alter table public.agent_events enable row level security;
alter table public.event_outbox enable row level security;
alter table public.artifacts enable row level security;

-- Workspace owner can read its workspace. Mutations go through the control plane.
create policy "workspace owner reads workspace"
  on public.workspaces for select to authenticated
  using (owner_user_id = (select auth.uid()));

-- All child rows are visible only to the owning user.
create policy "workspace owner reads projects"
  on public.projects for select to authenticated
  using (exists (
    select 1 from public.workspaces w
    where w.id = workspace_id and w.owner_user_id = (select auth.uid())
  ));

create policy "workspace owner reads devices"
  on public.devices for select to authenticated
  using (exists (
    select 1 from public.workspaces w
    where w.id = workspace_id and w.owner_user_id = (select auth.uid())
  ));

create policy "workspace owner reads provider connections"
  on public.provider_connections for select to authenticated
  using (exists (
    select 1 from public.workspaces w
    where w.id = workspace_id and w.owner_user_id = (select auth.uid())
  ));

create policy "workspace owner reads agents"
  on public.agents for select to authenticated
  using (exists (
    select 1 from public.workspaces w
    where w.id = workspace_id and w.owner_user_id = (select auth.uid())
  ));

create policy "workspace owner reads runs"
  on public.agent_runs for select to authenticated
  using (exists (
    select 1 from public.workspaces w
    where w.id = workspace_id and w.owner_user_id = (select auth.uid())
  ));

create policy "workspace owner reads approvals"
  on public.approvals for select to authenticated
  using (exists (
    select 1 from public.workspaces w
    where w.id = workspace_id and w.owner_user_id = (select auth.uid())
  ));

create policy "workspace owner reads events"
  on public.agent_events for select to authenticated
  using (exists (
    select 1 from public.workspaces w
    where w.id = workspace_id and w.owner_user_id = (select auth.uid())
  ));

create policy "workspace owner reads artifacts"
  on public.artifacts for select to authenticated
  using (exists (
    select 1 from public.workspaces w
    where w.id = workspace_id and w.owner_user_id = (select auth.uid())
  ));

-- Authenticated clients have read-only access. Operational writes must pass
-- through the control-plane API, where policy, idempotency, audit and outbox
-- logic are enforced. Supabase service-role credentials must remain server-only.
revoke all on public.workspaces, public.projects, public.devices,
  public.provider_connections, public.agents, public.agent_runs,
  public.approvals, public.agent_events, public.event_outbox,
  public.artifacts from anon, authenticated;

grant select on public.workspaces, public.projects, public.devices,
  public.provider_connections, public.agents, public.agent_runs,
  public.approvals, public.agent_events, public.artifacts to authenticated;

-- No UPDATE/DELETE policies are created on agent_events. The API must also
-- expose no endpoint for mutating or deleting historical event records.
