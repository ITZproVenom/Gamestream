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
- Settings: opt-in toggle, pending count, Upload now, Clear queue
- Success status example: `ok 200 · inserted 2`

## Edge Function

- Name: `game-diagnostics`
- Source in repo: `supabase/functions/game-diagnostics/index.ts`
- Project ref: `fswswvhpszebuxnloysy`
- Auth: JWT required; function uses `SUPABASE_SERVICE_ROLE_KEY` from function secrets

### Deploy

```bash
supabase functions deploy game-diagnostics --project-ref fswswvhpszebuxnloysy
```

## Table

`public.diagnostics` columns (verified via REST schema probes):

| column     | type        |
|------------|-------------|
| id         | bigint      |
| created_at | timestamptz |
| event_type | text        |
| payload    | jsonb       |

RLS / grants: anon cannot SELECT or INSERT (returns `[]` / 401). Rows are only visible in the Supabase dashboard or with service_role.

## Verification (anon-safe)

```bash
curl -sS -X POST "$SUPABASE_URL/functions/v1/game-diagnostics" \
  -H "Authorization: Bearer $ANON_KEY" -H "apikey: $ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"event_type":"diagnostic","message":"batch","platform":"ios","events":[{"event":"probe","props":{"k":"v"}}]}'
# → {"ok":true,"inserted":1}
```

Then in SQL editor (owner):

```sql
select id, created_at, event_type, payload
from public.diagnostics
order by id desc
limit 20;
```
