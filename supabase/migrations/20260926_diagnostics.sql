-- GameStream diagnostics table + RLS (reference migration)
-- Project: fswswvhpszebuxnloysy
-- Writes ONLY via Edge Function game-diagnostics (service_role).
-- Anon/authenticated clients must NOT read or insert directly.

create table if not exists public.diagnostics (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  event_type text not null default 'diagnostic',
  payload jsonb not null default '{}'::jsonb
);

create index if not exists diagnostics_created_at_idx on public.diagnostics (created_at desc);
create index if not exists diagnostics_event_type_idx on public.diagnostics (event_type);

alter table public.diagnostics enable row level security;

-- Deny direct client access (service_role bypasses RLS).
drop policy if exists "diagnostics_no_anon_select" on public.diagnostics;
drop policy if exists "diagnostics_no_anon_insert" on public.diagnostics;
drop policy if exists "diagnostics_no_anon_update" on public.diagnostics;
drop policy if exists "diagnostics_no_anon_delete" on public.diagnostics;

-- Explicit deny-style policies for authenticated/anon if any residual grants exist.
-- Prefer revoke privileges:
revoke all on table public.diagnostics from anon, authenticated;
grant select, insert, update, delete on table public.diagnostics to service_role;

-- Optional: allow service_role already has full access by default in Supabase.
