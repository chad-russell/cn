# ── gateway: Public Ingress (Caddy) ─────────────────────────────────
#
# Terminates TLS for all *.crussell.io public hostnames and reverse-proxies
# to backends over the Nebula overlay. TLS is auto-provisioned by Caddy via
# Let's Encrypt HTTP-01 (Caddy answers the challenge on :80 and serves the
# HTTP→HTTPS redirect) — NO Route53 DNS challenge, NO secrets on this
# public VPS. Ports 80 and 443 are opened in configuration.nix.
#
# Internal (*.internal.crussell.io) traffic bypasses the gateway entirely:
# public DNS resolves *.internal.crussell.io to bees (10.10.0.6), where
# bees's own Caddy terminates TLS via the Route53 DNS challenge wildcard.
#
# This replaced the old nginx TCP-passthrough → bees design, which made
# bees a single point of failure for all public routes (the 2026-06-13
# outage was caused by bees's Caddy being down after a power-outage reboot).
# Now each backend is reached independently over Nebula from the gateway.

{ config, lib, pkgs, ... }:

{
  services.caddy = {
    enable = true;
    # ACME account email. Caddy auto-provisions a cert per hostname via
    # HTTP-01; no environmentFile / Route53 credentials required here.
    email = "chaddouglasrussell@gmail.com";

    virtualHosts."homeassistant.crussell.io".extraConfig = ''
      # Home Assistant has `use_x_forwarded_for: true` with a `trusted_proxies`
      # list. Only bees (10.10.0.6) is trusted there, so an X-Forwarded-For from
      # gateway (10.10.0.2) makes HA return 400. Strip the XFF header so HA
      # treats gateway as a direct (accepted) client.
      # Preferred long-term fix: add 10.10.0.2 to HA trusted_proxies in
      # configuration.yaml, then remove this header_up override to restore
      # real client IPs in HA.
      reverse_proxy 10.10.0.51:8123 {
        header_up -X-Forwarded-For
      }
    '';

    virtualHosts."jellyfin.crussell.io".extraConfig = ''
      reverse_proxy 10.10.0.6:8096
    '';

    virtualHosts."photos.crussell.io".extraConfig = ''
      reverse_proxy 10.10.0.6:2283
    '';

    virtualHosts."datenight.crussell.io".extraConfig = ''
      reverse_proxy 10.10.0.6:7890
    '';
  };
}
