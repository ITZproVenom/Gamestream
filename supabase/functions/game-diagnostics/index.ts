import "jsr:@supabase/functions-js/edge-runtime.d.ts";

/**
 * game-diagnostics — production Edge Function (v7)
 *
 * Project: fswswvhpszebuxnloysy
 * Table: public.diagnostics
 * Auth: verify_jwt=true; service_role server-side only.
 * Client: GameStream iOS DiagnosticsStore (anon JWT only).
 */

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const allowedEvents = new Set([
  "layout_warning", "webview_error", "webview_failed", "webview_loaded", "webview_created", "webview_reload",
  "play_error", "search_error", "search_started", "search_success", "search_failed",
  "navigation", "navigation_error", "network_error", "connection_lost", "connection_restored",
  "performance", "memory_warning", "diagnostic", "opt_in", "manual_upload",
  "app_launch", "app_background", "app_foreground", "app_session_start", "app_session_end",
  "login_started", "login_success", "login_failed", "logout",
  "game_launch", "game_launch_failed", "game_start", "game_exit",
  "streaming_started", "streaming_failed", "streaming_ended", "session_expired",
  "launch_duration", "webview_load_duration", "game_start_duration",
]);

function cleanString(value: unknown, max: number): string | null {
  if (value === null || value === undefined) return null;
  const s = String(value).trim();
  return s ? s.slice(0, max) : null;
}

function numOrNull(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim() !== "") {
    const n = Number(value);
    return Number.isFinite(n) ? n : null;
  }
  return null;
}

/** Parse ISO-8601 / common date strings into ISO for timestamptz columns. */
function tsOrNull(value: unknown): string | null {
  if (value === null || value === undefined) return null;
  if (typeof value === "number" && Number.isFinite(value)) {
    return new Date(value).toISOString();
  }
  const s = String(value).trim();
  if (!s) return null;
  const d = new Date(s);
  if (Number.isNaN(d.getTime())) return null;
  return d.toISOString();
}

function normalizeEvent(event: Record<string, unknown>, body: Record<string, unknown>) {
  const rawType = event.event_type ?? event.event ?? event.type ?? "diagnostic";
  const eventType = String(rawType);
  const safeType = allowedEvents.has(eventType) ? eventType : "diagnostic";
  const props =
    event.props && typeof event.props === "object"
      ? (event.props as Record<string, unknown>)
      : event.properties && typeof event.properties === "object"
        ? (event.properties as Record<string, unknown>)
        : {};
  const payload =
    event.props || event.properties
      ? {
          ts: event.ts ?? event.event_at ?? null,
          event: event.event ?? safeType,
          event_id: event.event_id ?? null,
          session_id: event.session_id ?? null,
          props,
          app: event.app ?? body.app ?? null,
          build: event.build ?? body.build_number ?? null,
          platform: event.platform ?? body.platform ?? "ios",
          feature: event.feature ?? null,
          game_title: event.game_title ?? props.game_title ?? null,
        }
      : event.payload && typeof event.payload === "object"
        ? event.payload
        : event;
  const device =
    body.device && typeof body.device === "object"
      ? (body.device as Record<string, unknown>)
      : {};
  return {
    app_version: cleanString(event.app ?? body.app ?? body.app_version, 64),
    build_number: cleanString(event.build ?? body.build_number, 32),
    ios_version: cleanString(body.ios_version ?? device.system, 32),
    device_model: cleanString(body.device_model ?? device.model, 64),
    screen_width: numOrNull(event.screen_width ?? body.screen_width),
    screen_height: numOrNull(event.screen_height ?? body.screen_height),
    event_type: safeType,
    feature: cleanString(event.feature ?? body.feature, 128),
    session_id: cleanString(event.session_id ?? props.session_id, 64),
    event_id: cleanString(event.event_id, 64),
    event_at: tsOrNull(event.event_at ?? event.ts),
    platform: cleanString(event.platform ?? body.platform ?? "ios", 32),
    game_title: cleanString(event.game_title ?? props.game_title, 128),
    duration_ms: numOrNull(event.duration_ms ?? props.duration_ms),
    game_id: cleanString(event.game_id ?? props.game_id, 64),
    error_category: cleanString(event.error_category ?? props.error_category, 64),
    error_code: cleanString(event.error_code ?? props.error_code, 64),
    payload,
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "method_not_allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
  try {
    const body = await req.json();
    if (!body || typeof body !== "object") throw new Error("invalid_payload");
    const payloadBody = body as Record<string, unknown>;
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceRoleKey) throw new Error("server_not_configured");
    const rawEvents = Array.isArray(payloadBody.events) ? payloadBody.events : [payloadBody];
    const events = rawEvents
      .filter((event): event is Record<string, unknown> => !!event && typeof event === "object" && !Array.isArray(event))
      .map((event) => normalizeEvent(event, payloadBody));
    if (events.length === 0) throw new Error("empty_events");
    const response = await fetch(`${supabaseUrl}/rest/v1/diagnostics`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: serviceRoleKey,
        Authorization: `Bearer ${serviceRoleKey}`,
        Prefer: "return=minimal",
      },
      body: JSON.stringify(events),
    });
    if (!response.ok) {
      const detail = await response.text();
      console.error("diagnostics insert failed", response.status, detail.slice(0, 500));
      throw new Error("database_insert_failed");
    }
    return new Response(JSON.stringify({ ok: true, inserted: events.length }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("diagnostics error", error);
    return new Response(JSON.stringify({ error: "invalid_or_failed_request" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
