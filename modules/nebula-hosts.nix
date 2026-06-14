# ── Nebula Host Entries ────────────────────────────────────────────
#
# Adds /etc/hosts entries for all Nebula overlay IPs.
# Imported by base-server.nix so every connected machine can
# resolve nebula hostnames. Also import on roaming clients (thinkpad, etc.).

{ config, lib, ... }:

{
  networking.extraHosts = ''
    10.10.0.1   nebula-lh
    10.10.0.2   nebula-hetzner
    10.10.0.3   nas
    10.10.0.6   bees
    10.10.0.11  misc
    10.10.0.12  bee
    10.10.0.10  think
    10.10.0.51  homeassistant
  '';
}
