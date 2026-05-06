# ── SearXNG Meta Search Engine ───────────────────────────────────
#
# Native NixOS SearXNG service with local Redis for caching.
# Migrated from the old hub Podman pod (searxng + valkey containers).
# Stateless — no data to migrate.

{ config, lib, pkgs, ... }:

let
  secretFile = "/var/lib/searxng/secret.env";
in
{
  services.searx = {
    enable = true;
    package = pkgs.searxng;

    # Create a local Redis instance for SearXNG caching
    redisCreateLocally = true;

    # Use built-in web server (fine behind Caddy for homelab traffic)
    configureUwsgi = false;

    settings = {
      use_default_settings = true;

      server = {
        bind_address = "0.0.0.0";
        port = 8080;
        secret_key = "@SEARXNG_SECRET@";
        image_proxy = true;
      };

      search = {
        safe_search = 0;
        autocomplete = "duckduckgo";
        default_lang = "en";
        # Enable JSON API for programmatic access (pi agent, etc.)
        formats = [ "html" "json" ];
      };

      ui = {
        static_use_hash = true;
        default_locale = "en";
        query_in_title = true;
        infinite_scroll = true;
        default_theme = "simple";
        theme_args.simple_style = "auto";
      };
    };

    # Secret key loaded from environment file (generated on first activation)
    environmentFile = secretFile;
  };

  # ── Generate secret on first activation ────────────────────────
  # TODO: Move to agenix once age key is deployed to k2
  system.activationScripts.searxng-secret = lib.stringAfter [ "users" ] ''
    if [ ! -f ${secretFile} ]; then
      mkdir -p /var/lib/searxng
      echo "SEARXNG_SECRET=$(head -c 32 /dev/urandom | base64 | tr -d '\n')" > ${secretFile}
      chmod 600 ${secretFile}
      chown searx:searx ${secretFile} 2>/dev/null || true
    fi
  '';

  # Caddy on k2 proxies to this port
  networking.firewall.allowedTCPPorts = [ 8080 ];
}
