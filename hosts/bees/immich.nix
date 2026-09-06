# ── Immich Photo Server ───────────────────────────────────────────
# Photos are on NFS at /mnt/photos (already mounted in configuration.nix).

{ config, lib, pkgs, ... }:

{
  services.immich = {
    enable = true;
    host = "0.0.0.0";
    port = 2283;
    openFirewall = true;
    mediaLocation = "/mnt/photos";
    machine-learning.enable = true;
  };

  # Immich needs read access to the NFS photos mount.
  # NAS files are owned by crussell:users (gid 100); add immich to that
  # group so it can traverse directories with "other" permissions denied.
  users.groups.nas-photos = { gid = 1000; };
  users.users.immich.extraGroups = [ "nas-photos" "users" ];
  systemd.services.immich-server.serviceConfig.SupplementaryGroups =
    [ "redis-immich" "nas-photos" "users" ];

  # Reduce Redis log verbosity
  services.redis.servers.immich.logLevel = "warning";

  # 26.05 ships immich 2.7.5, marked insecure (CVE-2026-59258 album-role
  # escalation, CVE-2026-82272; both need an authenticated editor account —
  # family-only instance, and 2.7.5 is what already ran pre-upgrade).
  # Real fix = immich 3.x (in nixpkgs unstable / 26.11) — upgrade separately.
  nixpkgs.config.permittedInsecurePackages = [ "immich-2.7.5" ];
}
