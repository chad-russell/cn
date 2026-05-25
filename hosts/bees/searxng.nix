# ── SearXNG Meta Search Engine ───────────────────────────────────

{ config, lib, pkgs, ... }:

let
  secretFile = "/var/lib/searxng/secret.env";
in
{
  services.searx = {
    enable = true;
    package = pkgs.searxng;
    redisCreateLocally = true;
    configureUwsgi = false;

    settings = {
      use_default_settings = true;

      server = {
        bind_address = "0.0.0.0";
        port = 8888;
        secret_key = "@SEARXNG_SECRET@";
        image_proxy = true;
      };

      search = {
        safe_search = 0;
        autocomplete = "duckduckgo";
        default_lang = "en";
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

    environmentFile = secretFile;
  };

  system.activationScripts.searxng-secret = lib.stringAfter [ "users" ] ''
    if [ ! -f ${secretFile} ]; then
      mkdir -p /var/lib/searxng
      echo "SEARXNG_SECRET=$(head -c 32 /dev/urandom | base64 | tr -d '\n')" > ${secretFile}
      chmod 600 ${secretFile}
      chown searx:searx ${secretFile} 2>/dev/null || true
    fi
  '';

}
