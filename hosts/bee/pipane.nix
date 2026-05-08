# ── Pipane on bee ──────────────────────────────────────────────────
#
# Web UI for the pi coding agent on the dev server.
# Served via Caddy (on bees) at https://pi-bee.internal.crussell.io
# Caddy proxies to this host's Nebula IP (10.10.0.12:8222).

{ ... }:

{
  imports = [ ../../modules/pipane.nix ];

  services.pipane = {
    enable = true;
    port = 8222;
    openFirewall = true; # Caddy on bees (10.10.0.6) needs to reach this
  };
}
