import "jsr:@supabase/functions-js/edge-runtime.d.ts";

/**
 * game-diagnostics — production-aligned Edge Function (v2)
 *
 * Project: fswswvhpszebuxnloysy
 * Table: public.diagnostics (uuid PK, device columns, jsonb payload)
 * Auth: verify_jwt=true; service_role used only server-side for inserts.
 * Client: GameStream iOS DiagnosticsStore (anon JWT only).
 */

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const allowedEvents = new Set([
  "layout_warning",
  "webview_error",
  "play_error",
  "search_error",
  "navigation_error",
  "network_error",
  "performance",
  "memory_warning",
  "diagnostic",
  "opt_in",
  "manual_upload",
]);

function cleanString(value: unknown, max: number): string | null {
  return value ? String(value).slice(0, max) : null;
}

function normalizeEvent(event: Record<string, unknown>, body: Record<string, unknown>) {
  const rawType = event.event_type ?? event.event ?? event.type ?? "diagnostic";
  const eventType = String(rawType);
  const safeType = allowedEvents.has(eventType) ? eventType : "diagnostic";

  // iOS sends `props`; older clients may send `properties` or embed payload.
  const payload =
    event.properties && typeof event.properties === "object"
      ? event.properties
      : event.props && typeof event.props === "object"
        ? {
            ...(event as Record<string, unknown>),
            // Keep structured fields the iOS client already puts on the event.
          }
      : event.payload && typeof event.payload === "object"
        ? event.payload
        : event;

  const device =
    body.device && typeof body.device === "object"
      ? (body.device as Record<string, unknown>)
      : {};

  return {
    app_version: cleanString(body.app ?? body.app_version, 64),
    build_number: cleanString(body.build_number, 32),
    ios_version: cleanString(body.ios_version ?? device.system, 32),
    device_model: cleanString(body.device_model ?? device.model, 64),
    screen_width: typeof body.screen_width === "number" ? body.screen_width : null,
    screen_height: typeof body.screen_height === "number" ? body.screen_height : null,
    event_type: safeType,
    feature: cleanString(event.feature ?? body.feature, 128),
    payload,
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "method_not_allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    const body = await req.json();

    if (!body || typeof body !== "object") {
      throw new Error("invalid_payload");
    }

    const payloadBody = body as Record<string, unknown>;

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error("server_not_configured");
    }

    const rawEvents = Array.isArray(payloadBody.events)
      ? payloadBody.events
      : [payloadBody];

    const events = rawEvents
      .filter(
        (event): event is Record<string, unknown> =>
          !!event && typeof event === "object" && !Array.isArray(event),
      )
      .map((event) => normalizeEvent(event, payloadBody));

    if (events.length === 0) {
      throw new Error("empty_events");
    }

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
