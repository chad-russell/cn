# ── Nebula Host Entries ────────────────────────────────────────────
#
# Adds /etc/hosts entries for all Nebula overlay IPs.
# Imported by base-server.nix so every connected machine can
# resolve nebula hostnames. Also import on roaming clients (thinkpad, etc.).
#
# k1–k4 decommissioned 2026-05-05 (services migrated to bees + bee).
# k1 still on Nebula at 10.10.0.4 but idle; k2–k4 have Nebula disabled.
# bees took over k2's Nebula identity (10.10.0.6).

{ config, lib, ... }:

{
  networking.extraHosts = ''
    10.10.0.1   nebula-lh
    10.10.0.2   nebula-hetzner
    10.10.0.3   nas
    10.10.0.6   bees
    10.10.0.12  bee
    10.10.0.10  think
  '';
}
