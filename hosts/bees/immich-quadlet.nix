# ── Immich via Podman Quadlets (phase-1 migration target) ─────────
#
# Self-contained module installing the two immich quadlets as system
# units. NOT imported by hosts/bees/configuration.nix yet — the cutover
# commit (phase C, after gate H1) does that, alongside disabling
# services.immich and re-adding native postgresql/redis explicitly
# (see docs/immich-loop/PLAN.md D6/D9).
#
# Auth design (PLAN D8 discovery, 2026-09-06): the live `immich` PG
# role has NO password (peer auth over the unix socket) and
# redis-immich listens on its unix socket only (no TCP). So the
# containers auth exactly like the native services did — uid 991 peer
# + socket gid 992 — and NO secret material exists. There is no env
# file and therefore no agenix entry. If TCP auth is ever needed, add
# secrets/immich-env.age + age.secrets + EnvironmentFile then.
#
# Ids: immich = 991:993 (FACTS.md), redis-immich = 992.

{ config, lib, pkgs, ... }:

{
  environment.etc."containers/systemd/immich-server.container" = {
    source = ./immich-server.container;
    mode = "0644";
  };
  environment.etc."containers/systemd/immich-machine-learning.container" = {
    source = ./immich-machine-learning.container;
    mode = "0644";
  };

  # DB-independent local state on NVMe: the ML model cache.
  # (Media, thumbnails, profile, encoded video all stay in /mnt/photos.)
  systemd.tmpfiles.rules = [
    "d /var/lib/immich-quadlet 0750 991 993 -"
    "d /var/lib/immich-quadlet/ml-cache 0750 991 993 -"
  ];
}
