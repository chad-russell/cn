# ── Pipane on bees ────────────────────────────────────────────────
#
# Web UI for the pi coding agent on the production server.
# Served via Caddy at https://pi-bees.internal.crussell.io

{ ... }:

{
  imports = [ ../../modules/pipane.nix ];

  services.pipane = {
    enable = true;
    port = 8222;
    openFirewall = false; # Caddy is on the same host — no need to open externally
  };
}
