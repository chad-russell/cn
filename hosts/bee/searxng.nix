# ── SearXNG: self-hosted meta-search engine ────────────────────────
#
# Provides free, unlimited web search for Hermes' web_search toolset.
# Hermes connects via SEARXNG_URL=http://127.0.0.1:8888 (set in
# hermes-bee-env.age). SearXNG aggregates 70+ search engines (Google,
# Bing, DuckDuckGo, Brave, etc.) and exposes a JSON API for programmatic
# access.
#
# Localhost-only binding: no Caddy/TLS needed, no firewall exposure.
# Redis provides caching and (optionally) bot protection / rate limiting.

{ config, ... }:

{
  services.searx = {
    enable = true;
    redisCreateLocally = true;
    environmentFile = config.age.secrets.searx-secret.path;

    settings = {
      use_default_settings = true;

      server = {
        port = 8888;
        bind_address = "127.0.0.1";
        secret_key = "@SEARX_SECRET_KEY@";
        method = "GET";
      };

      # Enable JSON output format — required for Hermes API access
      search = { formats = [ "html" "json" ]; };

      general = {
        instance_name = "bee-search";
        debug = false;
      };

      # Disable the rate limiter and bot protection — localhost only,
      # and enabling them requires a public instance URL which we don't have.
      server.limiter = false;
      server.public_instance = false;

      # Reasonable timeouts for backend engine queries
      outgoing = {
        request_timeout = 10.0;
        max_request_timeout = 15.0;
      };

      # Use Redis for caching (improves response time for repeat queries)
      valkey.url = "unix://${config.services.redis.servers.searx.unixSocket}";
    };
  };

  # Ensure the age secret is decrypted before SearXNG starts
  age.secrets.searx-secret.file = ../../secrets/searx-secret.age;
}
