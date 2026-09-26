-- Analytics v2: error_code + richer views (applied via Supabase MCP)
ALTER TABLE public.diagnostics ADD COLUMN IF NOT EXISTS error_code text;
CREATE INDEX IF NOT EXISTS diagnostics_error_code_idx ON public.diagnostics (error_code) WHERE error_code IS NOT NULL;
CREATE INDEX IF NOT EXISTS diagnostics_duration_ms_idx ON public.diagnostics (duration_ms) WHERE duration_ms IS NOT NULL;

-- Views: analytics_event_summary, analytics_error_summary, analytics_app_version_summary,
-- analytics_device_summary, analytics_game_summary, analytics_daily_summary,
-- analytics_session_summary, analytics_failure_rates
-- (full definitions applied live; see Supabase migration diagnostics_error_code_and_analytics_views_v2)
