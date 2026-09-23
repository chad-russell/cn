# ── Mastra Factory — agent-powered SDLC (mastra.internal.crussell.io) ──
#
# Self-hosted Mastra Factory (https://factory.mastra.ai): issue → plan →
# implement → review environment running persistent coding agents. Factory
# UI at /, Mastra Studio at /studio — one Node server. Podman quadlets on
# bees, mirroring the kan pattern:
#
#   mastra.network             — bridge network (DNS: mastra ↔ mastra-postgres)
#   mastra-postgres.service    — pgvector/pgvector:pg18, named volume
#                                mastra_postgres_data (restic-covered via
#                                /var/lib/containers/storage/volumes in
#                                backup.nix — no extra path needed)
#   mastra.service             — localhost/mastra-factory:latest on
#                                127.0.0.1:8094, Restart=always +
#                                StartLimitIntervalSec=0 (always trying to
#                                be up, per Chad)
#   mastra-image-build.service — oneshot image build (see below)
#
# Ingress: bees Caddy mastra.internal.crussell.io → 127.0.0.1:8094
# (routes/internal/mastra.caddy — flush_interval -1 + 360s read_timeout for
# streaming agent sessions).
#
# Template provenance (2026-09-23): `npx create-factory@latest --no-platform`
# (github.com/mastra-ai/softwarefactory-template), vendored at
# ./mastra/factory. Deltas from the template, both marked "cn delta" in-file:
#   - factory/package.json: `npm run build` bundles the Studio UI (--studio)
#   - factory/src/mastra/index.ts: encrypt stored credentials even with auth
#     disabled (template skips encryption when MASTRACODE_AUTH_DISABLED=1)
# Upgrades: re-scaffold the template, reapply those two deltas, diff the rest
# against git history, then restart mastra-image-build + mastra.
#
# Decisions (2026-09-23, Chad):
#   - No auth provider: MASTRACODE_AUTH_DISABLED=1. Mastra auth is optional
#     and the route is internal-only (public DNS → Nebula 10.10.0.6); the
#     overlay is the gate. Revisit if the route ever leaves the overlay.
#   - Sandboxes: FACTORY_SANDBOX_PROVIDER=local — agent sessions check repos
#     out inside the container under the mastra_sandboxes volume (git, node,
#     openssh, curl baked into the image). Follow-up: explore self-hosted
#     sandbox providers (E2B-compatible) before letting untrusted repos run.
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
  environment.etc."mastra-build-storage.conf" = {
    source = ./mastra-build-storage.conf;
    mode = "0644";
  };

  # Build the server image before mastra.service starts (the quadlet has
  # Requires=/After= on this unit).
  #
  # Two-store dance, same reasoning as thinkpad-image-build: podman build
  # runs in the NATIVE-btrfs build store (mastra-build-storage.conf — the
  # default overlay-on-btrfs store pays the fuse-overlayfs tax on every
  # layer commit), but the quadlet runs from the DEFAULT root store — so a
  # changed image is `podman save | podman load`ed across. The load is gated
  # on the store-path-derived version tag: the ${./mastra/factory} context
  # store path hash changes iff the vendored project or Containerfile
  # change, so unchanged boots skip the build-transfer entirely (the btrfs
  # store still warms the layer cache).
  systemd.services.mastra-image-build = {
    description = "Mastra Factory — build server image";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    onFailure = [ "ntfy-failure@mastra-image-build.service" ];
    path = with pkgs; [ podman coreutils gnugrep systemd ];
    script = let
      ctx = "${./mastra/factory}";
      cf = "${./mastra/Containerfile}";
      # bash
    in ''
      set -euo pipefail
      BUILD() {
        CONTAINERS_STORAGE_CONF=/etc/mastra-build-storage.conf podman "$@"
      }
      ver="$(basename "$ctx")"  # store path name = content hash
      tag="localhost/mastra-factory:$ver"

      BUILD build --network=host -t "$tag" -f "$cf" "$ctx"

      if podman image exists "$tag"; then
        echo "image $tag already in the default store — skipping transfer"
      else
        echo "loading $tag into the default store"
        BUILD save "$tag" | podman load
        # New image — bounce the quadlet so it leaves the old one. Inside
        # the if-guard, so unchanged boots never restart the server.
        systemctl try-restart mastra.service
      fi
      # Instant; keeps `latest` honest even if a tag was removed by hand.
      podman tag "$tag" localhost/mastra-factory:latest

      # Best-effort pruning of superseded version tags; running containers
      # make an rmi fail harmlessly.
      for old in $(podman images --format '{{.Repository}}:{{.Tag}}' \
                     | grep '^localhost/mastra-factory:' | grep -vF ":$ver" | grep -v ':latest'); do
        podman rmi "$old" >/dev/null 2>&1 || true
      done
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # Root: the build store + default store are root's.
      User = "root";
      Nice = 10;
    };
    unitConfig = {
      # Boot-time image builds can take minutes on first run / after a
      # template bump; never time them out.
      TimeoutStartSec = "infinity";
      # Keep retrying a failed build rather than wedging the unit.
      StartLimitIntervalSec = 0;
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
