# ── Mastra Factory — agent-powered SDLC (mastra.internal.crussell.io) ──
#
# Self-hosted Mastra Factory (https://factory.mastra.ai): issue → plan →
# implement → review environment running persistent coding agents. Factory
# UI at /, Mastra Studio at /studio — one Node server. Podman quadlets on
# bees, mirroring the kan pattern:
#
#   mastra-postgres.service  — pgvector/pgvector:pg18, named volume
#                              mastra_postgres_data (restic-covered via
#                              /var/lib/containers/storage/volumes in
#                              backup.nix — no extra path needed)
#   mastra.service           — CI-built image from the zot registry on
#                              127.0.0.1:8094, Restart=always +
#                              StartLimitIntervalSec=0 (always trying to
#                              be up, per Chad), AutoUpdate=registry
#   mastra.network           — bridge network (DNS: mastra ↔ mastra-postgres)
#
# Image pipeline (NOT built by this flake — no vendored project here):
#   repo:  git.crussell.io/chad/mastra-factory — Factory server template
#          (`npx create-factory@latest --no-platform`) + Containerfile;
#          the two deltas vs upstream (build --studio; encrypt stored
#          credentials even with auth disabled) are marked "cn delta"
#          there and documented in its README
#   CI:    that repo's workflow builds on the bees `nix-host` runner and
#          pushes :latest + :sha-<git-sha> to 10.10.0.6:5000 (zot; the
#          retention policy in hosts/bees/zot-config.json keeps :latest +
#          the last 5 sha- tags)
#   pull:  this module marks 10.10.0.6:5000 as an insecure registry so the
#          SYSTEM podman can pull plain-HTTP for the quadlet (transport
#          security is the Nebula overlay — same reasoning as zot's
#          --tls-verify=false pushes)
#   roll:  podman-auto-update.timer (04:10 nightly) recreates mastra when
#          :latest moves; only AutoUpdate= units are touched. Rollback =
#          point Image= at an older sha- tag and restart mastra.
#
# Ingress: bees Caddy mastra.internal.crussell.io → 127.0.0.1:8094
# (routes/internal/mastra.caddy — flush_interval -1 + 360s read_timeout for
# streaming agent sessions).
#
# Decisions (2026-09-23, Chad):
#   - No auth provider: MASTRACODE_AUTH_DISABLED=1. Mastra auth is optional
#     and the route is internal-only (public DNS → Nebula 10.10.0.6); the
#     overlay is the gate. Revisit if the route ever leaves the overlay.
#   - Sandboxes: FACTORY_SANDBOX_PROVIDER=local — agent sessions check repos
#     out inside the container under the mastra_sandboxes volume (git, node,
#     openssh, curl baked into the image). Follow-up: explore self-hosted
#     sandbox providers before letting untrusted repos run.
#   - GitHub App deferred: UI + agents + Studio work without it; the
#     intake → plan → PR loop needs a GITHUB_APP_* env group later (all
#     env-gated in the entry — extend factory-env.age + the GitHub App
#     callback URL, no code change).
#
# Secrets: /run/agenix/factory-env (secrets/factory-env.age):
#   POSTGRES_PASSWORD, DATABASE_URL (→ mastra-postgres:5432),
#   FACTORY_CREDENTIAL_ENCRYPTION_KEY (base64 32B — losing it makes stored
#   provider credentials unreadable; see factory docs on rotation),
#   GITHUB_APP_WEBHOOK_SECRET (stable state-signing secret; becomes the real
#   webhook secret when the GitHub App lands).
#
# Verify: systemctl is-active mastra mastra-postgres;
# curl -s http://127.0.0.1:8094/health; https://mastra.internal.crussell.io

{ config, lib, pkgs, ... }:

{
  age.secrets.factory-env = {
    file = ../../secrets/factory-env.age;
    mode = "0600";
  };

  environment.etc."containers/systemd/mastra.container" = {
    source = ./mastra/mastra.container;
    mode = "0644";
  };
  environment.etc."containers/systemd/mastra-postgres.container" = {
    source = ./mastra/mastra-postgres.container;
    mode = "0644";
  };
  environment.etc."containers/systemd/mastra.network" = {
    source = ./mastra/mastra.network;
    mode = "0644";
  };

  # The zot registry is plain HTTP bound to bees's Nebula IP only (access
  # control = overlay membership, transport security = the tunnel). Mark it
  # insecure so the SYSTEM podman can pull the mastra-factory image for the
  # quadlet — CI pushes use per-command --tls-verify=false instead.
  virtualisation.containers.registries.insecure = [ "10.10.0.6:5000" ];

  # Nightly image refresh for AutoUpdate= quadlets (mastra is the only
  # opt-in on bees). 04:10 — inside the quiet-hours patch window. (26.05's
  # podman module has no autoUpdate option, so service + timer live here.)
  systemd.services.podman-auto-update = {
    description = "Podman auto-update (AutoUpdate= registry quadlets)";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.podman}/bin/podman auto-update";
    };
  };
  systemd.timers."podman-auto-update" = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "04:10";
      Persistent = true;
      RandomizedDelaySec = "10m";
    };
  };

  # Alert if the server stops answering its health endpoint (the unit's own
  # Restart=always handles crash loops; this catches "down for good").
  homelab.freshnessChecks.mastra = {
    description = "Mastra Factory (mastra.internal.crussell.io)";
    extraPath = [ pkgs.curl ];
    checkCommand = ''
      code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 http://127.0.0.1:8094/health || echo 000)
      echo "GET /health → $code"
      [ "$code" = "200" ]
    '';
  };
}
