# ── Kan (kan.bn): open-source Trello alternative ───────────────────
#
# Self-hosted Kan behind the gateway's public Caddy at
# https://trello.crussell.io (basic_auth gated). Runs as podman quadlets
# on bees:
#
#   kan.network          — bridge network (DNS: kan-web ↔ kan-postgres)
#   kan-postgres.service — Postgres 15, named volume kan_postgres_data
#   kan-migrate.service  — one-shot drizzle migrations (native service;
#                          `podman run --rm` per run, so image bumps
#                          re-run migrations on the next restart)
#   kan-web.service      — ghcr.io/kanbn/kan:latest on 127.0.0.1:3300
#
# Secrets in /run/agenix/kan-env (agenix): POSTGRES_PASSWORD,
# POSTGRES_URL, BETTER_AUTH_SECRET, KAN_ADMIN_API_KEY.
# First user to sign up becomes workspace owner → sign-up is disabled
# AFTER the first login works (NEXT_PUBLIC_DISABLE_SIGN_UP=true ships
# pre-set; flip to false in kan.container and redeploy if a re-signup
# is ever needed).
#
# Verify: https://trello.crussell.io (basic auth) → Kan login page.

{ config, lib, pkgs, ... }:

{
  age.secrets.kan-env = {
    file = ../../secrets/kan-env.age;
    mode = "0600";
  };

  environment.etc."containers/systemd/kan.container" = {
    source = ./kan.container;
    mode = "0644";
  };
  environment.etc."containers/systemd/kan-postgres.container" = {
    source = ./kan-postgres.container;
    mode = "0644";
  };
  environment.etc."containers/systemd/kan.network" = {
    source = ./kan.network;
    mode = "0644";
  };

  # One-shot migration runner. Native service (not a quadlet): quadlet
  # [Service] pass-through can't express Type=oneshot + RemainAfterExit
  # cleanly, and `podman run --rm` per start means image updates re-run
  # migrations automatically.
  systemd.services.kan-migrate = {
    description = "Kan (kan.bn) — one-shot DB migrations";
    after = [ "network-online.target" "kan-postgres.service" ];
    wants = [ "network-online.target" ];
    requires = [ "kan-postgres.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      EnvironmentFile = [ config.age.secrets.kan-env.path ];
      ExecStart = pkgs.writeShellScript "kan-migrate" ''
        exec ${pkgs.podman}/bin/podman run --rm \
          --name kan-migrate \
          --network kan.network \
          --env-file "$ENVIRONMENT_FILE" \
          ghcr.io/kanbn/kan-migrate:latest
      '';
    };
  };

  system.activationScripts.kan-dirs = lib.stringAfter [ "users" ] ''
    mkdir -p /var/lib/kan
    chmod 755 /var/lib/kan
  '';
}
