# ── Beszel Monitoring Hub (bees) ────────────────────────────────────
#
# Beszel is a lightweight server-monitoring tool (single Go binary +
# SQLite). The hub runs on bees and serves the web UI + the PocketBase
# REST API on 127.0.0.1:8091, fronted by the internal Caddy route
# `beszel.internal.crussell.io`. (Port 8091, not Beszel's default 8090,
# because ntfy-sh already listens on 8090 on this host.)
#
# Agents on the monitored hosts (bees, bee, nas, gateway) connect OUT to
# this hub over the Nebula overlay via WebSocket using a universal token,
# so no inbound port is required anywhere. See modules/beszel-agent.nix.
#
# Both the hub and agent binaries ship in the single nixpkgs `beszel`
# package (beszel-hub / beszel-agent / fetchsmartctl) and are updated
# automatically with `nix flake update`.

{ config, lib, pkgs, ... }:

{
  # Monitor bees itself with a local agent. The hub and agent share the
  # same `beszel` user/group.
  imports = [ ../../modules/beszel-agent.nix ];
  services.beszel-agent.enable = true;

  users.users.beszel = {
    isSystemUser = true;
    group = "beszel";
    home = "/var/lib/beszel";
    createHome = false;
  };
  users.groups.beszel = { };

  systemd.services.beszel = {
    description = "Beszel monitoring hub";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    # Used for notification links and agent-config generation in the UI.
    environment.APP_URL = "https://beszel.internal.crussell.io";

    serviceConfig = {
      ExecStart = "${pkgs.beszel}/bin/beszel-hub serve --http 127.0.0.1:8091 --dir /var/lib/beszel";
      User = "beszel";
      Group = "beszel";
      StateDirectory = "beszel";
      WorkingDirectory = "/var/lib/beszel";
      Restart = "on-failure";
      RestartSec = 5;

      # Hardening. PocketBase only needs to write its SQLite DB + files to
      # the StateDirectory (/var/lib/beszel), which stays writable.
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      ProtectClock = true;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      LockPersonality = true;
      RestrictSUIDSGID = true;
    };
  };
}
