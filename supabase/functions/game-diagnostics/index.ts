/**
 * game-diagnostics — Supabase Edge Function (v2)
 *
 * Contract used by GameStream iOS DiagnosticsStore:
 *   POST /functions/v1/game-diagnostics
 *   Authorization: Bearer <anon JWT>
 *   Body:
 *     {
 *       event_type?: "diagnostic",
 *       message?: string,
 *       platform?: string,
 *       app?: string,
 *       device?: { model?: string, system?: string },
 *       events?: Array<{ event?: string, props?: object, properties?: object, ts?: string, app?: string, platform?: string }>
 *     }
 *
 * Behavior:
 *   - Requires a valid JWT (gateway / function verify_jwt).
 *   - If `events` is a non-empty array → insert one public.diagnostics row per event.
 *   - If `events` is omitted / null → insert a single row from top-level fields.
 *   - If `events` is [] → 400 (nothing to insert).
 *   - Uses service_role only inside this function (never shipped to the client).
 *   - Returns { ok: true, inserted: N }.
 *
 * Table (expected):
 *   public.diagnostics (
 *     id bigint generated always as identity primary key,
 *     created_at timestamptz default now(),
 *     event_type text,
 *     payload jsonb
 *   )
 * RLS: anon cannot SELECT/INSERT directly; only this function (service role) writes.
 *
 * Deploy:
 *   supabase functions deploy game-diagnostics --project-ref fswswvhpszebuxnloysy
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type IncomingEvent = {
  event?: string;
  props?: Record<string, unknown>;
  properties?: Record<string, unknown>;
  ts?: string;
  app?: string;
  platform?: string;
  [key: string]: unknown;
};

type Body = {
  event_type?: string;
  message?: string;
  platform?: string;
  app?: string;
  device?: Record<string, unknown>;
  events?: IncomingEvent[] | null;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }

  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) {
    return json({ error: "server_misconfigured" }, 500);
  }

  let body: Body = {};
  try {
    body = (await req.json()) as Body;
  } catch {
    body = {};
  }

  const eventType = (body.event_type || "diagnostic").toString();
  // Keep a soft allow-list; unknown types still store under diagnostic for forward compat.
  const normalizedType = eventType === "diagnostic" ? "diagnostic" : "diagnostic";

  const rows: { event_type: string; payload: Record<string, unknown> }[] = [];

  if (Array.isArray(body.events)) {
    if (body.events.length === 0) {
      return json({ error: "invalid_or_failed_request" }, 400);
    }
    for (const ev of body.events) {
      const props = (ev.props ?? ev.properties ?? {}) as Record<string, unknown>;
      rows.push({
        event_type: normalizedType,
        payload: {
          event: ev.event ?? body.message ?? "event",
          props,
          ts: ev.ts ?? null,
          app: ev.app ?? body.app ?? null,
          platform: ev.platform ?? body.platform ?? null,
          device: body.device ?? null,
          message: body.message ?? null,
        },
      });
    }
  } else {
    // Single-event / top-level shape
    rows.push({
      event_type: normalizedType,
      payload: {
        event: body.message ?? "diagnostic",
        props: {},
        app: body.app ?? null,
        platform: body.platform ?? null,
        device: body.device ?? null,
        message: body.message ?? null,
      },
    });
  }

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data, error } = await admin.from("diagnostics").insert(rows).select("id");

  if (error) {
    console.error("database_insert_failed", error.message);
    return json({ error: "database_insert_failed", detail: error.message }, 500);
  }

  const inserted = Array.isArray(data) ? data.length : rows.length;
  return json({ ok: true, inserted }, 200);
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}
