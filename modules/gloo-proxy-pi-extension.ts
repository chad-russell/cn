import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

const PROXY_URL = process.env.GLOO_PROXY_URL || "http://10.10.0.6:4637/v1";
const API_KEY = process.env.GLOO_API_KEY || "";

export default async function (pi: ExtensionAPI) {
  let models: any[] = [];

  if (!API_KEY) {
    console.error("[gloo-proxy] GLOO_API_KEY env var not set (expected client_id:client_secret)");
    return;
  }

  try {
    const res = await fetch(`${PROXY_URL}/models`, {
      headers: { Authorization: `Bearer ${API_KEY}` },
    });
    if (!res.ok) throw new Error(`Fetch failed: ${res.status}`);
    const json = (await res.json()) as { data: any[] };
    models = json.data;
  } catch (err) {
    console.error(`[gloo-proxy] Failed to fetch models from ${PROXY_URL}/models: ${err}`);
    console.error("[gloo-proxy] Is the gloo-proxy service running? (systemctl status gloo-proxy)");
    return;
  }

  pi.registerProvider("gloo", {
    baseUrl: PROXY_URL,
    apiKey: API_KEY,
    api: "openai-completions",
    models: models.map((m) => ({
      id: m.id,
      name: m.id.replace(/^gloo-/, ""),
      reasoning: m.supports_reasoning ?? false,
      input: m.supports_vision ? ["text", "image"] : ["text"],
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
      contextWindow: m.context_window ?? 128000,
      maxTokens: m.max_output_tokens ?? 16384,
    })),
  });

  console.log(`[gloo-proxy] Registered ${models.length} models from Gloo`);
}
