# ── Nebula Host Entries ────────────────────────────────────────────
#
# /etc/hosts entries for all Nebula overlay IPs, generated from
# lib/host-meta.nix (the single source of truth). Imported by
# base-server.nix so every connected machine can resolve nebula
# hostnames. Also import on roaming clients (thinkpad, etc.).

{ lib, ... }:

let
  hostMeta = import ../lib/host-meta.nix;
in
{
  networking.extraHosts = lib.concatLines (
    lib.mapAttrsToList (name: h: "${h.nebula}\t${h.hostsName or name}") hostMeta
  );
}
