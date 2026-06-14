/**
 * Gloo AI → OpenAI-compatible proxy server
 *
 * Authenticates via the standard OpenAI Authorization header:
 *   Authorization: Bearer <client_id>:<client_secret>
 *
 * Endpoints:
 *   GET  /v1/models             → list available Gloo models
 *   GET  /v1/models/:id         → get a specific model
 *   POST /v1/chat/completions   → proxy chat completions (supports streaming)
 *
 * Also works without the /v1 prefix.
 */

const PORT = parseInt(process.env.PORT || "4637");

// ---------------------------------------------------------------------------
// Credential parsing
// ---------------------------------------------------------------------------
function parseCredentials(req: Request): { clientId: string; clientSecret: string } | null {
  const auth = req.headers.get("Authorization");
  if (!auth) return null;

  const match = auth.match(/^Bearer\s+(.+)$/i);
  if (!match) return null;

  const token = match[1];
  const colonIdx = token.indexOf(":");
  if (colonIdx === -1) return null;

  return {
    clientId: token.slice(0, colonIdx),
    clientSecret: token.slice(colonIdx + 1),
  };
}

function unauthorized(): Response {
  return Response.json(
    { error: { message: "Invalid or missing Authorization header. Use: Bearer <client_id>:<client_secret>", type: "authentication_error" } },
    { status: 401, headers: corsHeaders() },
  );
}

// ---------------------------------------------------------------------------
// Token management (per-credential cache)
// ---------------------------------------------------------------------------
const tokenCaches = new Map<string, { token: string; expiresAt: number }>();

function cacheKey(clientId: string, clientSecret: string): string {
  return `${clientId}:${clientSecret}`;
}

async function getToken(clientId: string, clientSecret: string): Promise<string> {
  const key = cacheKey(clientId, clientSecret);
  const cached = tokenCaches.get(key);
  if (cached && Date.now() < cached.expiresAt - 60_000) {
    return cached.token;
  }

  const auth = btoa(`${clientId}:${clientSecret}`);
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
  tokenCaches.set(key, {
    token: data.access_token,
    expiresAt: Date.now() + data.expires_in * 1000,
  });
  return data.access_token;
}

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------
const GLOO_MODELS_URL = "https://platform.ai.gloo.com/platform/v2/models";

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
async function handleCompletions(req: Request, clientId: string, clientSecret: string): Promise<Response> {
  let body: any;
  try {
    body = await req.json();
  } catch {
    return Response.json(
      { error: { message: "Invalid JSON body", type: "invalid_request_error" } },
      { status: 400, headers: corsHeaders() }
    );
  }

  if (!body.tradition) {
    body.tradition = "not_faith_specific";
  }

  if (!body.model && !body.auto_routing && !body.model_family) {
    body.auto_routing = true;
  }

  const token = await getToken(clientId, clientSecret);
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

    if (req.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders() });
    }

    if (path === "/health" || path === "/") {
      return Response.json({ status: "ok", service: "gloo-proxy" }, { headers: corsHeaders() });
    }

    const creds = parseCredentials(req);
    if (!creds) return unauthorized();

    if ((path === "/v1/models" || path === "/models") && req.method === "GET") {
      return handleModels();
    }

    const modelMatch = path.match(/^\/v1\/models\/(.+)$/) || path.match(/^\/models\/(.+)$/);
    if (modelMatch && req.method === "GET") {
      return handleModelGet(decodeURIComponent(modelMatch[1]));
    }

    if ((path === "/v1/chat/completions" || path === "/chat/completions") && req.method === "POST") {
      return handleCompletions(req, creds.clientId, creds.clientSecret);
    }

    return Response.json(
      { error: { message: `Not found: ${path}`, type: "invalid_request_error" } },
      { status: 404, headers: corsHeaders() }
    );
  },
});

console.log(`Gloo proxy running on http://localhost:${PORT}`);
