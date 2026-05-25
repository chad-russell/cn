/**
 * Gloo AI → OpenAI-compatible proxy server
 *
 * Usage:
 *   GLOO_CLIENT_ID=xxx GLOO_CLIENT_SECRET=yyy bun run gloo-proxy.ts
 *
 * Endpoints:
 *   GET  /v1/models             → list available Gloo models
 *   GET  /v1/models/:id         → get a specific model
 *   POST /v1/chat/completions   → proxy chat completions (supports streaming)
 *
 * Also works without the /v1 prefix.
 * Auth is accepted but not enforced (any key works, or none).
 */

const GLOO_CLIENT_ID = process.env.GLOO_CLIENT_ID || "";
const GLOO_CLIENT_SECRET = process.env.GLOO_CLIENT_SECRET || "";
const PORT = parseInt(process.env.PORT || "4637");

if (!GLOO_CLIENT_ID || !GLOO_CLIENT_SECRET) {
  console.error("Error: GLOO_CLIENT_ID and GLOO_CLIENT_SECRET env vars are required");
  process.exit(1);
}

// ---------------------------------------------------------------------------
// Token management
// ---------------------------------------------------------------------------
let tokenCache = { token: "", expiresAt: 0 };

async function getToken(): Promise<string> {
  if (tokenCache.token && Date.now() < tokenCache.expiresAt - 60_000) {
    return tokenCache.token;
  }

  const auth = btoa(`${GLOO_CLIENT_ID}:${GLOO_CLIENT_SECRET}`);
  const res = await fetch("https://platform.ai.gloo.com/oauth2/token", {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Authorization: `Basic ${auth}`,
    },
    body: "grant_type=client_credentials&scope=api/access",
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Token request failed (${res.status}): ${text}`);
  }

  const data = (await res.json()) as { access_token: string; expires_in: number };
  tokenCache = {
    token: data.access_token,
    expiresAt: Date.now() + data.expires_in * 1000,
  };
  return tokenCache.token;
}

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------
const GLOO_MODELS_URL = "https://platform.ai.gloo.com/platform/v2/models";

// Cache models for 5 minutes
let modelsCache = { data: null as any[] | null, expiresAt: 0 };

async function fetchGlooModels(): Promise<any[]> {
  if (modelsCache.data && Date.now() < modelsCache.expiresAt) {
    return modelsCache.data;
  }
  const res = await fetch(GLOO_MODELS_URL);
  if (!res.ok) throw new Error(`Failed to fetch models: ${res.status}`);
  const json = (await res.json()) as { data: any[] };
  modelsCache = { data: json.data, expiresAt: Date.now() + 300_000 };
  return json.data;
}

function toOpenAIModel(m: any) {
  return {
    id: m.id,
    object: "model" as const,
    created: Math.floor(Date.now() / 1000),
    owned_by: `gloo-${(m.family || "unknown").toLowerCase().replace(/\s+/g, "-")}`,
    // Extra metadata that some clients find useful
    context_window: m.context_window,
    max_output_tokens: m.max_output_tokens,
    supports_tools: m.supports_tools,
    supports_streaming: m.supports_streaming,
    supports_reasoning: m.supports_reasoning,
    supports_vision: m.supports_vision,
  };
}

async function handleModels(): Promise<Response> {
  const glooModels = await fetchGlooModels();
  return Response.json(
    { object: "list", data: glooModels.map(toOpenAIModel) },
    { headers: corsHeaders() }
  );
}

async function handleModelGet(id: string): Promise<Response> {
  const glooModels = await fetchGlooModels();
  const found = glooModels.find((m: any) => m.id === id);
  if (!found) return Response.json({ error: { message: `Model '${id}' not found`, type: "invalid_request_error" } }, { status: 404, headers: corsHeaders() });
  return Response.json(toOpenAIModel(found), { headers: corsHeaders() });
}

// ---------------------------------------------------------------------------
// Chat completions
// ---------------------------------------------------------------------------
async function handleCompletions(req: Request): Promise<Response> {
  let body: any;
  try {
    body = await req.json();
  } catch {
    return Response.json(
      { error: { message: "Invalid JSON body", type: "invalid_request_error" } },
      { status: 400, headers: corsHeaders() }
    );
  }

  // Default to not_faith_specific so Gloo doesn't inject faith perspective
  // into coding tasks. Client can override by explicitly setting tradition.
  if (!body.tradition) {
    body.tradition = "not_faith_specific";
  }

  // If no model specified and no auto_routing, enable auto_routing
  if (!body.model && !body.auto_routing && !body.model_family) {
    body.auto_routing = true;
  }

  const token = await getToken();
  const isStream = body.stream === true;

  const glooRes = await fetch("https://platform.ai.gloo.com/ai/v2/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify(body),
  });

  if (!glooRes.ok) {
    const errorText = await glooRes.text();
    console.error(`Gloo error (${glooRes.status}): ${errorText}`);
    return new Response(errorText, {
      status: glooRes.status,
      headers: { "Content-Type": "application/json", ...corsHeaders() },
    });
  }

  if (isStream) {
    // Forward the SSE stream directly
    return new Response(glooRes.body, {
      headers: {
        "Content-Type": "text/event-stream",
        "Cache-Control": "no-cache",
        Connection: "keep-alive",
        ...corsHeaders(),
      },
    });
  }

  const data = await glooRes.json();
  return Response.json(data, { headers: corsHeaders() });
}

// ---------------------------------------------------------------------------
// CORS
// ---------------------------------------------------------------------------
function corsHeaders(): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "*",
  };
}

// ---------------------------------------------------------------------------
// Server
// ---------------------------------------------------------------------------
Bun.serve({
  port: PORT,
  async fetch(req) {
    const url = new URL(req.url);
    const path = url.pathname;

    // CORS preflight
    if (req.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders() });
    }

    // Health check
    if (path === "/health" || path === "/") {
      return Response.json({ status: "ok", service: "gloo-proxy" }, { headers: corsHeaders() });
    }

    // Models
    if ((path === "/v1/models" || path === "/models") && req.method === "GET") {
      return handleModels();
    }

    // Single model
    const modelMatch = path.match(/^\/v1\/models\/(.+)$/) || path.match(/^\/models\/(.+)$/);
    if (modelMatch && req.method === "GET") {
      return handleModelGet(decodeURIComponent(modelMatch[1]));
    }

    // Chat completions
    if ((path === "/v1/chat/completions" || path === "/chat/completions") && req.method === "POST") {
      return handleCompletions(req);
    }

    return Response.json(
      { error: { message: `Not found: ${path}`, type: "invalid_request_error" } },
      { status: 404, headers: corsHeaders() }
    );
  },
});

console.log(`🚀 Gloo proxy running on http://localhost:${PORT}`);
console.log(`   GET  /v1/models`);
console.log(`   POST /v1/chat/completions`);
