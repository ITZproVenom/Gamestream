-- Diagnostics idempotency hardening.
-- Prevents duplicate rows when an upload is retried after an ambiguous network response.
-- event_id remains nullable for legacy rows; all newly emitted iOS events carry one.
create unique index if not exists diagnostics_event_id_unique_idx
on public.diagnostics (event_id)
where event_id is not null;
