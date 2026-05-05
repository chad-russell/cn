# ── Buildspace Dev Stack NixOS Module ────────────────────────────────
#
# Provides the Buildspace dev stack as user-level systemd services:
#   - Infra (postgres) via Podman Compose
#   - App dev servers (marketplace, login, runtime, studio, docs, super-admin, jobs)
#
# Buildspace and Gloo are mutually exclusive work contexts.
# All services run as user-level systemd units via loginctl linger.
#
# Usage:
#   systemctl --user start buildspace.target              # start everything
#   systemctl --user start buildspace-stack.target        # start stack
#   systemctl --user stop buildspace-marketplace.service  # stop individual service
#   journalctl --user -u buildspace-marketplace -f        # follow logs

{ config, lib, pkgs, ... }:

let
  cfg = config.services.buildspace;
  user = cfg.user;
  bsDir = cfg.buildspaceDir;

  # ── PATH for app dev server services ─────────────────────────────
  servicePath = lib.makeBinPath [
    pkgs.bun
    pkgs.nodejs_24
    pkgs.nodePackages.pnpm
  ] + ":/run/current-system/sw/bin";

  # ── PATH for infra services ──────────────────────────────────────
  infraPath = lib.makeBinPath [
    pkgs.podman
    pkgs.docker-compose
  ] + ":/run/current-system/sw/bin";

  # ── Prisma engine paths ──────────────────────────────────────────
  prismaEngines = lib.getBin pkgs.prisma-engines;
  prismaEnv = ''
    Environment=PRISMA_QUERY_ENGINE_BINARY=${prismaEngines}/bin/query-engine
    Environment=PRISMA_SCHEMA_ENGINE_BINARY=${prismaEngines}/bin/schema-engine
    Environment=PRISMA_FMT_BINARY=${prismaEngines}/bin/prisma-fmt
    Environment=PRISMA_CLI_QUERY_ENGINE_TYPE=binary
    Environment=PRISMA_CLIENT_ENGINE_TYPE=binary
    Environment=PRISMA_ENGINES_CHECKSUM_IGNORE_MISSING=1
  '';

  # ── App service definitions ──────────────────────────────────────
  appServices = {
    marketplace = {
      description = "Buildspace marketplace app";
      filter = "@buildspace/marketplace";
      port = 3000;
    };
    login = {
      description = "Buildspace login app";
      filter = "@buildspace/login";
      port = 3003;
    };
    runtime = {
      description = "Buildspace runtime app";
      filter = "@buildspace/runtime";
      port = 3002;
    };
    studio = {
      description = "Buildspace studio app";
      filter = "@buildspace/studio";
      port = 3005;
    };
    docs = {
      description = "Buildspace docs app";
      filter = "@buildspace/docs";
      port = 3004;
    };
    super-admin = {
      description = "Buildspace super-admin app";
      filter = "@buildspace/super-admin";
      port = 3006;
    };
    jobs = {
      description = "Buildspace jobs worker";
      filter = "@buildspace/jobs-app";
      port = 3010;
    };
  };

  # Generate systemd user unit file text for an app service
  mkAppUnit = name: svc: ''
    [Unit]
    Description=${svc.description}
    After=network-online.target buildspace-infra.target buildspace-deps.service
    Wants=network-online.target buildspace-infra.target buildspace-deps.service
    PartOf=buildspace-stack.target
    ConditionPathExists=${bsDir}/package.json
    ConditionPathExists=${bsDir}/.env

    [Service]
    Type=simple
    Environment=PATH=${servicePath}
    ${prismaEnv}
    EnvironmentFile=${bsDir}/.env
    WorkingDirectory=${bsDir}
    ExecStart=${pkgs.bash}/bin/bash -c 'exec ${pkgs.bun}/bin/bun --env-file=.env --filter ${svc.filter} dev'
    Restart=on-failure
    RestartSec=2

    [Install]
    WantedBy=buildspace-stack.target
  '';

  # ── Infra helpers ────────────────────────────────────────────────
  waitPostgres = pkgs.writeShellScript "buildspace-wait-postgres" ''
    echo "Waiting for Buildspace postgres..."
    for i in $(seq 1 60); do
      if podman exec buildspace_postgres_1 \
          pg_isready -U postgres -d postgres >/dev/null 2>&1; then
        echo "Postgres is ready."
        exit 0
      fi
      sleep 2
    done
    echo "ERROR: Postgres did not become ready" >&2
    exit 1
  '';

  # ── All user unit file contents ──────────────────────────────────
  userUnits =
    # Targets
    {
      "buildspace-infra.target" = ''
        [Unit]
        Description=Buildspace shared infra (compose)
        Wants=buildspace-infra-up.service
        After=buildspace-infra-up.service
      '';
      "buildspace-stack.target" = ''
        [Unit]
        Description=Buildspace local app stack
        Wants=${lib.concatStringsSep " "
          (["buildspace-infra.target" "buildspace-deps.service"]
          ++ (lib.mapAttrsToList (name: _: "buildspace-${name}.service") appServices))}
        After=buildspace-infra.target buildspace-deps.service
      '';
      "buildspace.target" = ''
        [Unit]
        Description=All Buildspace services
        Wants=buildspace-stack.target
        After=buildspace-stack.target
      '';
    }
    # Infra services
    // {
      "buildspace-infra-up.service" = ''
        [Unit]
        Description=Start Buildspace compose infra and wait for postgres

        [Service]
        Type=oneshot
        Environment=PATH=${infraPath}
        ExecStart=${pkgs.bash}/bin/bash -c 'podman compose -f /etc/buildspace/compose.yaml up -d && ${waitPostgres}'
        RemainAfterExit=yes
      '';
      "buildspace-deps.service" = ''
        [Unit]
        Description=Bootstrap Buildspace dependencies
        After=buildspace-infra.target
        Wants=buildspace-infra.target
        ConditionPathExists=${bsDir}/package.json
        PartOf=buildspace-stack.target

        [Service]
        Type=oneshot
        Environment=PATH=${servicePath}
        WorkingDirectory=${bsDir}
        ExecStart=${pkgs.bun}/bin/bun install --frozen-lockfile
        TimeoutStartSec=30min

        [Install]
        WantedBy=buildspace-stack.target
      '';
    }
    # App services
    // (lib.mapAttrs' (name: svc:
        lib.nameValuePair "buildspace-${name}.service" { text = mkAppUnit name svc; }
      ) appServices);

  # Script that writes all user unit files to ~/.config/systemd/user/
  installUserUnits = pkgs.writeShellScript "buildspace-install-user-units" ''
    UNIT_DIR="/home/${user}/.config/systemd/user"
    mkdir -p "$UNIT_DIR"

    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: content: ''
      cat > "$UNIT_DIR/${name}" << 'UNIT_EOF'
    ${if builtins.isAttrs content then content.text else content}
    UNIT_EOF
    '') userUnits)}

    # Fix ownership
    chown -R ${user}:users "$UNIT_DIR"

    # Reload systemd
    ${pkgs.sudo}/bin/sudo -u ${user} XDG_RUNTIME_DIR=/run/user/$(id -u ${user}) ${pkgs.systemd}/bin/systemctl --user daemon-reload
  '';

in
{
  options.services.buildspace = {
    enable = lib.mkEnableOption "Buildspace dev stack (infra + app services)";

    user = lib.mkOption {
      type = lib.types.str;
      default = "crussell";
      description = "User account that owns the Buildspace services and source repo";
    };

    buildspaceDir = lib.mkOption {
      type = lib.types.path;
      default = "/home/crussell/buildspace";
      description = "Path to the Buildspace source repo";
    };
  };

  config = lib.mkIf cfg.enable {

    # ── System packages ───────────────────────────────────────────
    environment.systemPackages = with pkgs; [
      bun
      nodejs_24
      nodePackages.pnpm
      podman
      docker-compose
      prisma-engines
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

    # ── Static files in /etc/buildspace/ ──────────────────────────
    environment.etc = {
      "buildspace/compose.yaml".source = ./buildspace/compose.yaml;
    };

    # ── Install user units on activation ──────────────────────────
    system.activationScripts.buildspace-user-units = lib.stringAfter [ "users" "etc" ] ''
      ${installUserUnits}
    '';

    # ── User linger ───────────────────────────────────────────────
    system.activationScripts.buildspace-linger = lib.stringAfter [ "users" ] ''
      ${pkgs.systemd}/bin/loginctl enable-linger ${user} 2>/dev/null || true
    '';
  };
}
