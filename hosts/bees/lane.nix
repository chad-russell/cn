# ── Lane: self-hosted Plane CE (project management, async work board) ──
#
# "Lane" is Chad's name for this instance (upstream project: Plane CE,
# AGPL-3.0, makeplane/plane v1.4.2). Shared kanban board for Chad + the
# Hermes agent(s); reachable at https://lane.internal.crussell.io
# (Nebula-only, via bees Caddy → 127.0.0.1:8100).
#
# Quadlets (system-level, root podman):
#
#   lane.network            — bridge network
#   lane-postgres.service   — postgres:15.7-alpine (ContainerName plane-db)
#   lane-redis.service      — valkey:7.2.11 (ContainerName plane-redis)
#   lane-mq.service         — rabbitmq:3.13.6 (ContainerName plane-mq)
#   lane-minio.service      — minio uploads (ContainerName plane-minio)
#   lane-migrator.service   — one-shot Django migrations
#   lane-api.service        — Django API (ContainerName api)
#   lane-worker.service     — celery worker
#   lane-beat.service       — celery beat
#   lane-live.service       — realtime (ContainerName live)
#   lane-web.service        — frontend (ContainerName web)
#   lane-space.service      — public docs (ContainerName space)
#   lane-admin.service      — instance admin (ContainerName admin)
#   lane-proxy.service      — nginx edge → 127.0.0.1:8100
#
# WHY the generic ContainerNames (web/api/space/admin/live/plane-*): the
# plane-proxy image hardcodes those upstream hostnames for routing — they
# are compose service names upstream. Units carry the lane- prefix instead;
# do NOT rename the containers unless proxy routing is reworked.
#
# Secrets: /run/agenix/lane-env (SECRET_KEY, LIVE_SERVER_SECRET_KEY,
# POSTGRES_PASSWORD, DATABASE_URL, REDIS_URL, AMQP_URL, RABBITMQ_DEFAULT_PASS,
# AWS_ACCESS_KEY_ID/SECRET_ACCESS_KEY, WEBHOOK_ALLOWED_IPS for Plane→bee
# webhook delivery). Regenerate via the generator note in
# secrets/lane-env.age's commit.
#
# Data: named volumes lane_* (covered by bees restic via
# /var/lib/containers/storage/volumes).
#
# Upgrades: bump the image tags, then `sudo systemctl restart
# lane-migrator.service lane-api.service lane-worker.service lane-beat.service`
# (migrator re-runs RemainAfterExit oneshot) and restart the static
# containers. Mirror upstream release notes for env changes.

{ config, lib, pkgs, ... }:

{
  age.secrets.lane-env = {
    file = ../../secrets/lane-env.age;
    mode = "0600";
  };

  environment.etc."containers/systemd/lane.network" = {
    source = ./lane.network;
    mode = "0644";
  };

  environment.etc."containers/systemd/lane-postgres.container" = {
    source = ./lane-postgres.container;
    mode = "0644";
  };
  environment.etc."containers/systemd/lane-redis.container" = {
    source = ./lane-redis.container;
    mode = "0644";
  };
  environment.etc."containers/systemd/lane-mq.container" = {
    source = ./lane-mq.container;
    mode = "0644";
  };
  environment.etc."containers/systemd/lane-minio.container" = {
    source = ./lane-minio.container;
    mode = "0644";
  };
  environment.etc."containers/systemd/lane-migrator.container" = {
    source = ./lane-migrator.container;
    mode = "0644";
  };
  environment.etc."containers/systemd/lane-api.container" = {
    source = ./lane-api.container;
    mode = "0644";
  };
  environment.etc."containers/systemd/lane-worker.container" = {
    source = ./lane-worker.container;
    mode = "0644";
  };
  environment.etc."containers/systemd/lane-beat.container" = {
    source = ./lane-beat.container;
    mode = "0644";
  };
  environment.etc."containers/systemd/lane-live.container" = {
    source = ./lane-live.container;
    mode = "0644";
  };
  environment.etc."containers/systemd/lane-web.container" = {
    source = ./lane-web.container;
    mode = "0644";
  };
  environment.etc."containers/systemd/lane-space.container" = {
    source = ./lane-space.container;
    mode = "0644";
  };
  environment.etc."containers/systemd/lane-admin.container" = {
    source = ./lane-admin.container;
    mode = "0644";
  };
  environment.etc."containers/systemd/lane-proxy.container" = {
    source = ./lane-proxy.container;
    mode = "0644";
  };
}
