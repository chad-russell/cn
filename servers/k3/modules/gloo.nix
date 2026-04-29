# ── Gloo Dev Stack NixOS Module ────────────────────────────────────
#
# Provides the full Gloo dev stack as user-level systemd services:
#   - Infra (postgres, rustfs, pgadmin) via Podman Compose
#   - App dev servers (gpl, hb-api, hb-web, storyhub, storyhub-worker, polymer)
#   - Agenix-managed secrets
#
# All services run as the configured user via systemd user units.
# No sudo required for daily operations (start/stop/logs).
#
# Usage:
#   systemctl --user start gloo-all.target          # start everything
#   systemctl --user start gloo-hummingbird.target   # start hb-api + hb-web
#   systemctl --user stop gloo-gpl.service           # stop individual service
#   journalctl --user -u gloo-polymer -f             # follow logs

{ config, lib, pkgs, ... }:

let
  cfg = config.services.gloo;
  user = cfg.user;
  glooDir = cfg.glooDir;

  # ── PATH for app dev server services ─────────────────────────────
  servicePath = lib.makeBinPath [
    pkgs.nodejs_24
    pkgs.nodePackages.pnpm
    pkgs.bun
  ] + ":/run/current-system/sw/bin";

  # ── PATH for infra services ──────────────────────────────────────
  infraPath = lib.makeBinPath [
    pkgs.podman
    pkgs.docker-compose
  ] + ":/run/current-system/sw/bin";

  # ── Agenix secret path (deterministic: /run/agenix/<name>) ───────
  secretsPath = "${config.age.secretsDir}/gloo-secrets";

  # ── App service definitions ──────────────────────────────────────
  # Each entry generates:
  #   - /etc/gloo/envs/<name>.env   (static env file)
  #   - /etc/systemd/user/gloo-<name>.service

  appServices = {
    gpl = {
      description = "Gloo GPL dev server";
      workingDir = "${glooDir}/360-gpl";
      execCmd = "npx next dev -H 0.0.0.0 -p 3106";
      port = 3106;
    };
    hb-api = {
      description = "Gloo Hummingbird API dev server";
      workingDir = "${glooDir}/360-hummingbird";
      execCmd = "pnpm --filter api dev";
      port = 8000;
    };
    hb-web = {
      description = "Gloo Hummingbird Web dev server";
      workingDir = "${glooDir}/360-hummingbird";
      execCmd = "pnpm --filter web dev -- --host 0.0.0.0 --port 3100";
      port = 3100;
    };
    storyhub = {
      description = "Gloo Storyhub dev server";
      workingDir = "${glooDir}/360-hummingbird/storyhub";
      execCmd = "npx next dev -H 0.0.0.0 --port 3007";
      port = 3007;
    };
    storyhub-worker = {
      description = "Gloo Storyhub worker dev server";
      workingDir = "${glooDir}/360-hummingbird";
      execCmd = "pnpm --filter storyhub-worker dev";
      port = 8001;
    };
    polymer = {
      description = "Gloo Polymer dev server";
      workingDir = "${glooDir}/360-polymer/apps/polymer";
      execCmd = "${pkgs.bash}/bin/bash -c 'rm -f .next/dev/lock && exec pnpm exec next dev --turbo --hostname 0.0.0.0 --port 3001'";
      port = 3001;
    };
  };

  # Generate systemd user unit file text for an app service
  mkAppUnit = name: svc: ''
    [Unit]
    Description=${svc.description}
    After=network-online.target gloo-infra.target
    Wants=network-online.target
    PartOf=gloo-all.target

    [Service]
    Type=simple
    Environment=PATH=${servicePath}
    EnvironmentFile=/etc/gloo/envs/${name}.env
    EnvironmentFile=${secretsPath}
    WorkingDirectory=${svc.workingDir}
    ExecStart=${svc.execCmd}
    Restart=on-failure
    RestartSec=2

    [Install]
    WantedBy=gloo-all.target
  '';

  # ── Infra helper scripts ─────────────────────────────────────────

  waitPostgres = pkgs.writeShellScript "gloo-wait-postgres" ''
    echo "Waiting for Gloo postgres..."
    for i in $(seq 1 60); do
      if ${lib.getExe' pkgs.podman "podman"} exec gloo_postgres_1 \
          pg_isready -U postgres -d postgres >/dev/null 2>&1; then
        echo "Postgres is ready."
        exit 0
      fi
      sleep 2
    done
    echo "ERROR: Postgres did not become ready" >&2
    exit 1
  '';

  initDb = pkgs.writeShellScript "gloo-init-db" ''
    echo "Creating databases..."
    for db in gpl_db storyhub polymer; do
      ${lib.getExe' pkgs.podman "podman"} exec gloo_postgres_1 \
        psql -U postgres -c "CREATE DATABASE $db;" 2>/dev/null \
        && echo "  ✓ $db" || echo "  ✓ $db (already exists)"
    done
  '';

  initBuckets = pkgs.writeShellScript "gloo-init-buckets" ''
    export AWS_ACCESS_KEY_ID=rustfsadmin
    export AWS_SECRET_ACCESS_KEY=rustfsadmin
    export AWS_DEFAULT_REGION=us-east-1
    ENDPOINT="http://127.0.0.1:9000"

    echo "Waiting for RustFS..."
    for i in $(seq 1 30); do
      ${lib.getExe pkgs.awscli2} s3api list-buckets --endpoint-url "$ENDPOINT" >/dev/null 2>&1 && break
      sleep 2
    done

    if ! ${lib.getExe pkgs.awscli2} s3api list-buckets --endpoint-url "$ENDPOINT" >/dev/null 2>&1; then
      echo "ERROR: RustFS not ready" >&2
      exit 1
    fi

    for b in gpl-assets storyhub-media-items polymer-bucket; do
      ${lib.getExe pkgs.awscli2} s3api create-bucket --bucket "$b" --endpoint-url "$ENDPOINT" >/dev/null 2>&1 \
        && echo "  ✓ $b" || true
    done
  '';

in
{
  options.services.gloo = {
    enable = lib.mkEnableOption "Gloo dev stack (infra + app services)";

    user = lib.mkOption {
      type = lib.types.str;
      default = "crussell";
      description = "User account that owns the Gloo services and source repos";
    };

    glooDir = lib.mkOption {
      type = lib.types.path;
      default = "/home/crussell/Gloo";
      description = "Parent directory containing Gloo source repos (360-*)";
    };
  };

  config = lib.mkIf cfg.enable {

    # ── Agenix secret ─────────────────────────────────────────────
    age.identityPaths = [ "/home/${user}/.config/age/key.txt" ];

    age.secrets.gloo-secrets = {
      file = ../secrets/gloo-secrets.env.age;
      owner = user;
    };

    # ── System packages ───────────────────────────────────────────
    environment.systemPackages = with pkgs; [
      nodejs_24
      nodePackages.pnpm
      bun
      podman
      docker-compose
      awscli2
      age
      git
      jq
    ];

    # ── Podman (rootless) ─────────────────────────────────────────
    virtualisation.podman = {
      enable = true;
      dockerCompat = true;
    };

    # ── Firewall: open app service ports ──────────────────────────
    networking.firewall.allowedTCPPorts =
      lib.mapAttrsToList (_: svc: svc.port) appServices;

    # ── Static files ──────────────────────────────────────────────
    environment.etc =

      # Compose file + per-service env files
      {
        "gloo/compose.yaml".source = ../gloo/compose.yaml;
      }
      // (lib.mapAttrs' (name: _:
          lib.nameValuePair "gloo/envs/${name}.env" {
            source = ../gloo/envs/${name}.env;
          }
        ) appServices)

      # ── Systemd user targets ──────────────────────────────────────
      // {
        "systemd/user/gloo-infra.target".text = ''
          [Unit]
          Description=Gloo shared infra (compose + init)
          Wants=gloo-infra-up.service gloo-init-db.service gloo-init-buckets.service
          After=gloo-infra-up.service
        '';

        "systemd/user/gloo-all.target".text = ''
          [Unit]
          Description=All Gloo dev servers
          Wants=${lib.concatStringsSep " "
            (lib.mapAttrsToList (name: _: "gloo-${name}.service") appServices)}
          After=gloo-infra.target
        '';

        "systemd/user/gloo-hummingbird.target".text = ''
          [Unit]
          Description=Gloo Hummingbird dev stack
          Wants=gloo-hb-api.service gloo-hb-web.service
        '';

        "systemd/user/gloo-storyhub.target".text = ''
          [Unit]
          Description=Gloo Storyhub dev stack
          Wants=gloo-storyhub.service gloo-storyhub-worker.service
        '';
      }

      # ── Infra services ────────────────────────────────────────────
      // {
        "systemd/user/gloo-infra-up.service".text = ''
          [Unit]
          Description=Start Gloo compose infra and wait for postgres

          [Service]
          Type=oneshot
          Environment=PATH=${infraPath}
          ExecStart=${pkgs.bash}/bin/bash -c '${lib.getExe' pkgs.podman "podman"} compose -f /etc/gloo/compose.yaml up -d && ${waitPostgres}'
          RemainAfterExit=yes
        '';

        "systemd/user/gloo-init-db.service".text = ''
          [Unit]
          Description=Create Gloo databases (idempotent)
          After=gloo-infra-up.service
          Wants=gloo-infra-up.service

          [Service]
          Type=oneshot
          Environment=PATH=${infraPath}
          ExecStart=${initDb}
        '';

        "systemd/user/gloo-init-buckets.service".text = ''
          [Unit]
          Description=Create Gloo S3 buckets in RustFS (idempotent)
          After=gloo-infra-up.service
          Wants=gloo-infra-up.service

          [Service]
          Type=oneshot
          TimeoutStartSec=5min
          Environment=PATH=${infraPath}
          ExecStart=${initBuckets}
        '';
      }

      # ── App services ──────────────────────────────────────────────
      // (lib.mapAttrs' (name: svc:
          lib.nameValuePair "systemd/user/gloo-${name}.service" {
            text = mkAppUnit name svc;
          }
        ) appServices);

    # ── User linger (services start at boot without login) ───────
    system.activationScripts.gloo-linger = lib.stringAfter [ "users" ] ''
      ${pkgs.systemd}/bin/loginctl enable-linger ${user} 2>/dev/null || true
    '';
  };
}
