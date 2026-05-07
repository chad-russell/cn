# ── Gloo Containerized Dev Stack NixOS Module ──────────────────────
#
# Containerized version of the Gloo dev stack using Podman Compose.
# Each app service runs in its own container via a single compose project.
#
# Coexists with the native Gloo module during migration.
# Enable with: services.gloo-containerized.enable = true;
#
# Usage:
#   systemctl --user start gloo-c-infra.target         # start infra
#   systemctl --user start gloo-c-hummingbird.target    # start hb-api + hb-web
#   systemctl --user start gloo-c-gpl.target            # start gpl (+ hb-api)
#   systemctl --user stop gloo-c-hb-web.service         # stop individual service
#   podman compose logs -f hb-api                       # follow logs

{ config, lib, pkgs, ... }:

let
  cfg = config.services.gloo-containerized;
  user = cfg.user;
  composeFile = "/etc/gloo-containerized/compose.yaml";

  # ── PATH for compose operations ──────────────────────────────────
  composePath = lib.makeBinPath [
    pkgs.podman
    pkgs.docker-compose
  ] + ":/run/current-system/sw/bin";

  # ── Podman socket for rootless compose ─────────────────────────
  dockerHost = "unix:///run/user/" + builtins.toString 1000 + "/podman/podman.sock";

  # ── Common compose wrapper args ──────────────────────────────────
  composeCmd = "${pkgs.bash}/bin/bash -c 'podman compose -f ${composeFile}'";

  # ── Agenix secret path ──────────────────────────────────────────
  secretsPath = "${config.age.secretsDir}/gloo-secrets";

  # ── Fix Prisma binary permissions ──────────────────────────────
  # Prisma generates engine binaries with 555 perms, which causes EACCES
  # in rootless podman with keep-id. This script runs on the host after
  # bootstrap to make them writable.
  fixPrismaPerms = pkgs.writeShellScript "gloo-c-fix-prisma-perms" ''
    echo "Fixing Prisma binary permissions..."
    for dir in ${glooDir}/360-hummingbird/api/generated \
               ${glooDir}/360-hummingbird/storyhub-prisma/generated \
               ${glooDir}/360-hummingbird/storyhub/generated; do
      if [ -d "$dir" ]; then
        chmod -R u+w "$dir" 2>/dev/null && echo "  ✓ $dir" || true
      fi
    done
  '';

  # ── Gloo source dir ────────────────────────────────────────────
  glooDir = "/home/${user}/Gloo";

  # ── Wait for postgres helper ────────────────────────────────────
  waitPostgres = pkgs.writeShellScript "gloo-c-wait-postgres" ''
    echo "Waiting for Gloo containerized postgres..."
    for i in $(seq 1 60); do
      if podman exec gloo-postgres-1 \
          pg_isready -U postgres -d postgres >/dev/null 2>&1; then
        echo "Postgres is ready."
        exit 0
      fi
      sleep 2
    done
    echo "ERROR: Postgres did not become ready" >&2
    exit 1
  '';

  # ── Init databases ──────────────────────────────────────────────
  initDb = pkgs.writeShellScript "gloo-c-init-db" ''
    echo "Creating databases..."
    for db in gpl_db storyhub polymer; do
      podman exec gloo-postgres-1 \
        psql -U postgres -c "CREATE DATABASE $db;" 2>/dev/null \
        && echo "  ✓ $db" || echo "  ✓ $db (already exists)"
    done
  '';

  # ── Init buckets ────────────────────────────────────────────────
  initBuckets = pkgs.writeShellScript "gloo-c-init-buckets" ''
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

  # ── All user unit file contents ──────────────────────────────────
  userUnits =
    # ── Targets ────────────────────────────────────────────────────
    {
      "gloo-c-infra.target" = ''
        [Unit]
        Description=Gloo containerized infra (compose + init)
        Wants=gloo-c-infra-up.service gloo-c-init-db.service gloo-c-init-buckets.service
        After=gloo-c-infra-up.service
      '';
      "gloo-c-all.target" = ''
        [Unit]
        Description=All Gloo containerized dev services
        Wants=gloo-c-hummingbird.target gloo-c-gpl.target gloo-c-polymer.target gloo-c-storyhub.target
        After=gloo-c-infra.target
      '';
      "gloo-c-hummingbird.target" = ''
        [Unit]
        Description=Gloo containerized Hummingbird stack
        Wants=gloo-c-hb-api.service gloo-c-hb-web.service
      '';
      "gloo-c-gpl.target" = ''
        [Unit]
        Description=Gloo containerized GPL stack
        Wants=gloo-c-hb-api.service gloo-c-gpl.service
      '';
      "gloo-c-polymer.target" = ''
        [Unit]
        Description=Gloo containerized Polymer stack
        Wants=gloo-c-polymer.service
      '';
      "gloo-c-storyhub.target" = ''
        [Unit]
        Description=Gloo containerized Storyhub stack
        Wants=gloo-c-storyhub.service gloo-c-storyhub-worker.service
      '';
    }
    # ── Infra services ─────────────────────────────────────────────
    // {
      "gloo-c-infra-up.service" = ''
        [Unit]
        Description=Start Gloo containerized compose infra and wait for postgres

        [Service]
        Type=oneshot
        Environment=PATH=${composePath}
        Environment=DOCKER_HOST=${dockerHost}
        ExecStart=${pkgs.bash}/bin/bash -c 'podman compose -f ${composeFile} up -d postgres rustfs pgadmin && ${waitPostgres}'
        RemainAfterExit=yes
      '';
      "gloo-c-init-db.service" = ''
        [Unit]
        Description=Create Gloo containerized databases (idempotent)
        After=gloo-c-infra-up.service
        Wants=gloo-c-infra-up.service

        [Service]
        Type=oneshot
        Environment=PATH=${composePath}
        Environment=DOCKER_HOST=${dockerHost}
        ExecStart=${initDb}
      '';
      "gloo-c-init-buckets.service" = ''
        [Unit]
        Description=Create Gloo containerized S3 buckets in RustFS (idempotent)
        After=gloo-c-infra-up.service
        Wants=gloo-c-infra-up.service

        [Service]
        Type=oneshot
        TimeoutStartSec=5min
        Environment=PATH=${composePath}
        Environment=DOCKER_HOST=${dockerHost}
        ExecStart=${initBuckets}
      '';
    }
    # ── Bootstrap services ─────────────────────────────────────────
    // {
      "gloo-c-bootstrap-hummingbird.service" = ''
        [Unit]
        Description=Bootstrap Gloo containerized Hummingbird deps (pnpm install + prisma generate)
        After=gloo-c-infra.target
        Wants=gloo-c-infra.target

        [Service]
        Type=oneshot
        TimeoutStartSec=30min
        Environment=PATH=${composePath}
        Environment=DOCKER_HOST=${dockerHost}
        ExecStart=${pkgs.bash}/bin/bash -c 'podman compose -f ${composeFile} run --rm hummingbird-bootstrap'
        ExecStartPost=${fixPrismaPerms}
      '';
      "gloo-c-bootstrap-gpl.service" = ''
        [Unit]
        Description=Bootstrap Gloo containerized GPL deps (pnpm install)
        After=gloo-c-infra.target
        Wants=gloo-c-infra.target

        [Service]
        Type=oneshot
        TimeoutStartSec=30min
        Environment=PATH=${composePath}
        Environment=DOCKER_HOST=${dockerHost}
        ExecStart=${pkgs.bash}/bin/bash -c 'podman compose -f ${composeFile} run --rm gpl-bootstrap'
      '';
      "gloo-c-bootstrap-polymer.service" = ''
        [Unit]
        Description=Bootstrap Gloo containerized Polymer deps (pnpm install)
        After=gloo-c-infra.target
        Wants=gloo-c-infra.target

        [Service]
        Type=oneshot
        TimeoutStartSec=30min
        Environment=PATH=${composePath}
        Environment=DOCKER_HOST=${dockerHost}
        ExecStart=${pkgs.bash}/bin/bash -c 'podman compose -f ${composeFile} run --rm polymer-bootstrap'
      '';
    }
    # ── App services ───────────────────────────────────────────────
    // {
      "gloo-c-hb-api.service" = ''
        [Unit]
        Description=Gloo containerized Hummingbird API
        After=gloo-c-infra.target
        Wants=gloo-c-infra.target
        PartOf=gloo-c-all.target

        [Service]
        Type=simple
        Environment=PATH=${composePath}
        Environment=DOCKER_HOST=${dockerHost}
        ExecStart=${pkgs.bash}/bin/bash -c 'podman compose -f ${composeFile} up hb-api'
        ExecStop=${pkgs.bash}/bin/bash -c 'podman compose -f ${composeFile} stop hb-api'
        Restart=on-failure
        RestartSec=5

        [Install]
        WantedBy=gloo-c-all.target
      '';
      "gloo-c-hb-web.service" = ''
        [Unit]
        Description=Gloo containerized Hummingbird Web
        After=gloo-c-infra.target gloo-c-hb-api.service
        Wants=gloo-c-infra.target gloo-c-hb-api.service
        PartOf=gloo-c-all.target

        [Service]
        Type=simple
        Environment=PATH=${composePath}
        Environment=DOCKER_HOST=${dockerHost}
        ExecStart=${pkgs.bash}/bin/bash -c 'podman compose -f ${composeFile} up hb-web'
        ExecStop=${pkgs.bash}/bin/bash -c 'podman compose -f ${composeFile} stop hb-web'
        Restart=on-failure
        RestartSec=5

        [Install]
        WantedBy=gloo-c-all.target
      '';
      "gloo-c-gpl.service" = ''
        [Unit]
        Description=Gloo containerized GPL
        After=gloo-c-infra.target gloo-c-hb-api.service
        Wants=gloo-c-infra.target gloo-c-hb-api.service
        PartOf=gloo-c-all.target

        [Service]
        Type=simple
        Environment=PATH=${composePath}
        Environment=DOCKER_HOST=${dockerHost}
        ExecStart=${pkgs.bash}/bin/bash -c 'podman compose -f ${composeFile} up gpl'
        ExecStop=${pkgs.bash}/bin/bash -c 'podman compose -f ${composeFile} stop gpl'
        Restart=on-failure
        RestartSec=5

        [Install]
        WantedBy=gloo-c-all.target
      '';
      "gloo-c-polymer.service" = ''
        [Unit]
        Description=Gloo containerized Polymer
        After=gloo-c-infra.target
        Wants=gloo-c-infra.target
        PartOf=gloo-c-all.target

        [Service]
        Type=simple
        Environment=PATH=${composePath}
        Environment=DOCKER_HOST=${dockerHost}
        ExecStart=${pkgs.bash}/bin/bash -c 'podman compose -f ${composeFile} up polymer'
        ExecStop=${pkgs.bash}/bin/bash -c 'podman compose -f ${composeFile} stop polymer'
        Restart=on-failure
        RestartSec=5

        [Install]
        WantedBy=gloo-c-all.target
      '';
      "gloo-c-storyhub.service" = ''
        [Unit]
        Description=Gloo containerized Storyhub
        After=gloo-c-infra.target
        Wants=gloo-c-infra.target
        PartOf=gloo-c-all.target

        [Service]
        Type=simple
        Environment=PATH=${composePath}
        Environment=DOCKER_HOST=${dockerHost}
        ExecStart=${pkgs.bash}/bin/bash -c 'podman compose -f ${composeFile} up storyhub'
        ExecStop=${pkgs.bash}/bin/bash -c 'podman compose -f ${composeFile} stop storyhub'
        Restart=on-failure
        RestartSec=5

        [Install]
        WantedBy=gloo-c-all.target
      '';
      "gloo-c-storyhub-worker.service" = ''
        [Unit]
        Description=Gloo containerized Storyhub Worker
        After=gloo-c-infra.target
        Wants=gloo-c-infra.target
        PartOf=gloo-c-all.target

        [Service]
        Type=simple
        Environment=PATH=${composePath}
        Environment=DOCKER_HOST=${dockerHost}
        ExecStart=${pkgs.bash}/bin/bash -c 'podman compose -f ${composeFile} up storyhub-worker'
        ExecStop=${pkgs.bash}/bin/bash -c 'podman compose -f ${composeFile} stop storyhub-worker'
        Restart=on-failure
        RestartSec=5

        [Install]
        WantedBy=gloo-c-all.target
      '';
    };

  # ── Script that writes all user unit files ──────────────────────
  installUserUnits = pkgs.writeShellScript "gloo-c-install-user-units" ''
    UNIT_DIR="/home/${user}/.config/systemd/user"
    mkdir -p "$UNIT_DIR"

    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: content: ''
      cat > "$UNIT_DIR/${name}" << 'UNIT_EOF'
    ${content}
    UNIT_EOF
    '') userUnits)}

    # Fix ownership
    chown -R ${user}:users "$UNIT_DIR"

    # Reload systemd
    ${pkgs.sudo}/bin/sudo -u ${user} XDG_RUNTIME_DIR=/run/user/$(id -u ${user}) ${pkgs.systemd}/bin/systemctl --user daemon-reload
  '';

in
{
  options.services.gloo-containerized = {
    enable = lib.mkEnableOption "Gloo containerized dev stack (podman compose per-service)";

    user = lib.mkOption {
      type = lib.types.str;
      default = "crussell";
      description = "User account that owns the Gloo services";
    };
  };

  config = lib.mkIf cfg.enable {

    # ── Agenix secret (shared with native gloo) ──────────────────
    age.identityPaths = [ "/home/${user}/.config/age/key.txt" ];

    age.secrets.gloo-secrets = {
      file = ../../secrets/gloo-secrets.env.age;
      owner = user;
    };

    # ── System packages ───────────────────────────────────────────
    environment.systemPackages = with pkgs; [
      podman
      docker-compose
      awscli2
      git
      jq
    ];

    # ── Podman (rootless) ─────────────────────────────────────────
    virtualisation.podman = {
      enable = true;
      dockerCompat = true;
    };

    # ── Firewall: same ports as native Gloo ───────────────────────
    # Phase 2 will handle port collision if running both simultaneously.
    networking.firewall.allowedTCPPorts = [
      5050   # pgadmin
      9000   # rustfs API
      9001   # rustfs console
      5433   # postgres
      8000   # hb-api
      3100   # hb-web
      3106   # gpl
      3001   # polymer
      3007   # storyhub
      8001   # storyhub-worker
    ];

    # ── Static files in /etc/gloo-containerized/ ──────────────────
    environment.etc = {
      "gloo-containerized/compose.yaml".source = ./gloo/compose.yaml;
      "gloo-containerized/Containerfile".source = ./gloo/Containerfile;
    } // (lib.listToAttrs (map
        (name: lib.nameValuePair "gloo-containerized/envs/${name}.env" {
          source = ./gloo/envs/${name}.env;
        })
        ["gpl" "hb-api" "hb-web" "polymer" "storyhub" "storyhub-worker"]
      ));

    # ── Install user units on activation ──────────────────────────
    system.activationScripts.gloo-c-user-units = lib.stringAfter [ "users" "etc" ] ''
      ${installUserUnits}
    '';

    # ── User linger ───────────────────────────────────────────────
    system.activationScripts.gloo-c-linger = lib.stringAfter [ "users" ] ''
      ${pkgs.systemd}/bin/loginctl enable-linger ${user} 2>/dev/null || true
    '';
  };
}
