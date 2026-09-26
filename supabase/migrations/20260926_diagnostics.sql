-- Reference schema matching LIVE public.diagnostics (project fswswvhpszebuxnloysy)
-- Do not assume this migration created the table; it documents production shape.
--
-- Live columns (verified 2026-09-26 via MCP):
--   id uuid PK default gen_random_uuid()
--   created_at timestamptz default now()
--   app_version, build_number, ios_version, device_model text
--   screen_width, screen_height float8
--   event_type text not null
--   feature text
--   payload jsonb default '{}'
--
-- RLS: enabled, no policies → anon/authenticated denied by default.
-- Table privileges still listed for anon/authenticated, but RLS blocks access.
-- Writes occur only via Edge Function game-diagnostics using service_role.

-- Idempotent ensure (safe if already applied):
create table if not exists public.diagnostics (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  app_version text,
  build_number text,
  ios_version text,
  device_model text,
  screen_width double precision,
  screen_height double precision,
  event_type text not null,
  feature text,
  payload jsonb not null default '{}'::jsonb
);

create index if not exists diagnostics_created_at_idx on public.diagnostics (created_at desc);
create index if not exists diagnostics_event_type_idx on public.diagnostics (event_type);

alter table public.diagnostics enable row level security;

-- Defense in depth: revoke direct client DML/SELECT if grants exist.
-- service_role continues to bypass RLS and retain access for the Edge Function.
revoke all on table public.diagnostics from anon, authenticated;
