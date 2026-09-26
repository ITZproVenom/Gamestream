# Diagnostics pipeline (iOS → Supabase)

## Path

```
iOS event
  → DiagnosticsStore.record (opt-in only, sanitized)
  → UserDefaults queue
  → automatic flush (~2.5s) or Settings "Upload now"
  → POST /functions/v1/game-diagnostics  (anon JWT)
  → Edge Function normalizes events[]
  → insert public.diagnostics (service_role, server-side only)
```

## Client

- File: `GameStream/Services/DiagnosticsStore.swift`
- Credential: **anon / publishable JWT only** (never service_role)
- Session: UUID `session_id` rotated on launch / long background
- Per-event: `event_id`, optional `duration_ms`, `game_id`, `error_category`, `error_code`
- Settings: opt-in toggle, pending count, Upload now, Clear queue

## Events (allow-listed)

Lifecycle: `app_launch`, `app_background`, `app_foreground`, `app_session_start`  
Auth: `login_started`, `login_success`, `login_failed`, `logout`  
Play: `game_launch`, `game_launch_failed`, `streaming_started`, `streaming_ended`, `streaming_failed`  
WebView: `webview_created`, `webview_loaded`, `webview_failed`  
Search: `search_started`, `search_success`, `search_failed`  
Other: `navigation`, `memory_warning`, `opt_in`, `manual_upload`

## Edge Function

- Name: `game-diagnostics` (v5+)
- Source: `supabase/functions/game-diagnostics/index.ts`
- Auth: JWT required; service_role server-side only

## Table `public.diagnostics`

Structured columns: `app_version`, `build_number`, `ios_version`, `device_model`, `screen_width/height`, `event_type`, `feature`, `session_id`, `duration_ms`, `game_id`, `error_category`, `error_code`, `payload` (jsonb).

## Analytics views

- `analytics_event_summary` — counts + avg/p50 duration by event
- `analytics_error_summary` — by event/category/code
- `analytics_app_version_summary` — launches/failures/streams by version
- `analytics_device_summary` — errors by device/iOS
- `analytics_game_summary` — per game_id launch/stream stats
- `analytics_daily_summary` — daily totals
- `analytics_session_summary` — per session timeline + had_failure
- `analytics_failure_rates` — game/stream/login fail % by app_version

## Example queries

```sql
SELECT * FROM analytics_failure_rates WHERE app_version = '2.0.1';
SELECT * FROM analytics_session_summary WHERE had_failure;
SELECT * FROM analytics_game_summary ORDER BY stream_failures DESC;
SELECT event_type, avg_duration_ms FROM analytics_event_summary WHERE avg_duration_ms IS NOT NULL;
```
