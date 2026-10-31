# ── bee: sweatshop (rootless quadlet, crussell) ───────────────────────
#
# Chad's personal software factory (repo: git.crussell.io/chad/sweatshop,
# GitHub chad-russell/sweatshop, checkout ~/sweatshop). ONE instance,
# image-era serving (sweatshop 0091, cutover 2026-10-31): this unit runs
# the CI-built zot image (10.10.0.6:5000/sweatshop/app:main) — the image
# entrypoint runs migrations then `next start`. Deploys are pull +
# restart by the repo's Forgejo deploy workflow; the checkout stays for
# ./dev one-offs but is no longer serving infrastructure. dsh is the
# emergency path if a deploy breaks it.
#
# Mechanics as hindsight.nix (D-017): materialize the quadlet files
# read-only under /etc, symlink into crussell's user quadlet search path,
# reload the user manager, enable.
#
# State lives in ~/.sweatshop-data (sqlite + WAL, the Workflow SDK local
# world, backups/, env/.env.local) — in bee's restic paths (backup.nix).
# Moved out of the checkout at the 0091 cutover; a cutover activation
# below performs the one-time move (idempotent). The nightly timer below
# writes a guaranteed-consistent copy, backups/nightly.db, an hour
# before the 00:00 (+≤1 h jitter) restic window.
#
# Skills store (sweatshop 0088): rootless rustfs sidecar in the same
# quadlet family — sweatshop-rustfs.container, bucket `skills`, nothing
# published (app reaches http://sweatshop-rustfs:9000 on sweatshop-
# harness; SKILLS_S3_* env in the checkout's .env.local, appended on
# the host post-deploy). Bucket bootstrapped by the bucket-init unit
# below. Per-project sidecar, not the nas shared instance (topology
# rule: docs/rustfs-migration/PLAN.md).
#
# Ingress: http://bee:3300 directly (LAN/Nebula, no auth — sweatshop's hard
# rule: a real verifier before any internet exposure). Previews:
# bees Caddy pv-*.internal.crussell.io → 10.10.0.12:3301
# (hosts/bees/caddy/routes/internal/previews.caddy).
{ config, lib, pkgs, ... }:

let
  checkout = "/home/crussell/sweatshop";
  # 0091: state dir, moved out of the checkout at the image-era cutover.
  dataDir = "/home/crussell/.sweatshop-data";
  # rustfs.container deploys alongside (quadlet, symlinked by the
  # activation below). rustfs-bucket-init.mjs is NOT a unit — the
  # bucket-init service below runs it in a one-off container on the
  # harness network (only members can reach the sidecar).
  units =
    [ "sweatshop.container" "sweatshop-harness.network" "rustfs.container" ];
in {
  # 0043 host channel: the exec tool's SSH key, mounted read-only into
  # the container (see sweatshop.container). owner=crussell per the
  # hindsight.nix precedent so the rootless user quadlet can read it.
  age.secrets.sweatshop-host-key = {
    file = ../../secrets/sweatshop-host-key.age;
    owner = "crussell";
    mode = "0400";
  };

  # Skills sidecar creds (RUSTFS_ACCESS_KEY/RUSTFS_SECRET_KEY — dedicated
  # pair, not the nas root keys). owner=crussell per hindsight-env
  # precedent: the ROOTLESS user quadlet reads it as EnvironmentFile.
  age.secrets.sweatshop-rustfs-env = {
    file = ../../secrets/sweatshop-rustfs-env.age;
    owner = "crussell";
    mode = "0400";
  };

  # The quadlet inputs + the bucket-bootstrap script (run by
  # sweatshop-rustfs-bucket-init below in a one-off container), both
  # materialized read-only under /etc/sweatshop.
  environment.etc = (lib.listToAttrs (map (u: {
    name = "sweatshop/${u}";
    value = {
      source = ./sweatshop + "/${u}";
      mode = "0444";
    };
  }) units)) // {
    "sweatshop/rustfs-bucket-init.mjs" = {
      source = ./sweatshop/rustfs-bucket-init.mjs;
      mode = "0444";
    };
  };

  system.activationScripts.sweatshop-quadlet =
    lib.stringAfter [ "users" "etc" "sweatshop-data-move" ] ''
      dest="/home/crussell/.config/containers/systemd"
      mkdir -p "$dest"
      chown crussell:users "$dest"
      for u in ${lib.concatStringsSep " " units}; do
        ln -sfn "/etc/sweatshop/$u" "$dest/$u"
        chown -h crussell:users "$dest/$u"
      done

      uid="$(id -u crussell 2>/dev/null || true)"
      if [ -n "$uid" ] && [ -d "/run/user/$uid" ]; then
        runuser -u crussell -- env XDG_RUNTIME_DIR="/run/user/$uid" \
          systemctl --user daemon-reload 2>/dev/null || true
        # Generated units cannot be `enable`d; [Install] WantedBy in the
        # .container wires boot start through the generator. Activation never
        # starts or restarts the app — the first start is the cut-over, and
        # every later restart belongs to the repo's deploy workflow.
      fi
    '';

  # ── 0091 cutover: one-time state move out of the checkout ────────
  # Idempotent; run BEFORE the quadlet activation above would start the
  # image unit against an empty data dir. Order: stringAfter ["users"]
  # is enough — it must merely precede any start of the new unit, and
  # activation never starts units.
  system.activationScripts.sweatshop-data-move = lib.stringAfter [ "users" ] ''
    if [ -d "${checkout}/data" ] && [ ! -e "${dataDir}" ]; then
      mv "${checkout}/data" "${dataDir}"
    fi
    mkdir -p "${dataDir}/env"
    # .env.local moves into the data dir (quadlet reads
    # ${dataDir}/env/.env.local); a symlink keeps the checkout's ./dev
    # path (and anything else referencing it) working.
    if [ -f "${checkout}/.env.local" ] && [ ! -e "${dataDir}/env/.env.local" ]; then
      mv "${checkout}/.env.local" "${dataDir}/env/.env.local"
      ln -sfn "${dataDir}/env/.env.local" "${checkout}/.env.local"
    fi
    chown -R crussell:users "${dataDir}"
    chmod 700 "${dataDir}" "${dataDir}/env"
    chmod 600 "${dataDir}/env/.env.local" 2>/dev/null || true
  '';

  # Consistent online copy of the app db (better-sqlite3 backup API, via the
  # repo's own script in a one-off container with the app's mounts).
  # Image-era (0091): the snapshot runs inside the SERVING image (it
  # carries scripts/ + @aws-sdk deps), against the bound data dir — no
  # checkout, no dev container. sqlite must quiesce first: stop the app
  # unit, snapshot, start again (the 23:00 blip is the trade for a
  # guaranteed-consistent nightly.db; same pattern as the pre-cutover
  # service's better-sqlite3 backup API, which required no stop).
  systemd.user.services.sweatshop-db-snapshot = {
    description = "sweatshop nightly db snapshot (backups/nightly.db)";
    onFailure = [ "ntfy-failure@sweatshop-db-snapshot.service" ];
    unitConfig = {
      ConditionUser = "crussell";
      ConditionPathExists = "${dataDir}/sweatshop.db";
    };
    path = [ pkgs.podman pkgs.bash pkgs.coreutils ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart =
        "${pkgs.bash}/bin/bash -c '${config.systemd.package}/bin/systemctl --user stop sweatshop.service && ${pkgs.podman}/bin/podman run --rm -v ${dataDir}:/app/data 10.10.0.6:5000/sweatshop/app:main node scripts/db-snapshot.mjs nightly; rc=$?; ${config.systemd.package}/bin/systemctl --user start sweatshop.service; exit $rc'";
    };
  };

  systemd.user.timers.sweatshop-db-snapshot = {
    wantedBy = [ "default.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 23:00";
      Persistent = true;
    };
  };

  # Idempotent skills-bucket bootstrap: sweatshop's S3 store does not
  # create its bucket (0088), and the sidecar publishes nothing — so
  # this runs the bootstrap script INSIDE a one-off container on
  # sweatshop-harness (sweatshop-db-snapshot mechanics), using the
  # app's own image + bundled @aws-sdk/client-s3. A green run proves
  # the app's exact client path (endpoint, path-style, SigV4) works.
  systemd.user.services.sweatshop-rustfs-bucket-init = {
    description = "sweatshop: create skills bucket in sweatshop-rustfs";
    onFailure = [ "ntfy-failure@sweatshop-rustfs-bucket-init.service" ];
    unitConfig.ConditionUser = "crussell";
    # Wait for the sidecar quadlet (generated unit, needs the generator
    # to have run: Activation above reloads the user manager first).
    after = [ "sweatshop-rustfs.service" ];
    wants = [ "sweatshop-rustfs.service" ];
    wantedBy = [ "default.target" ];
    path = [ pkgs.podman pkgs.bash ];
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = config.age.secrets.sweatshop-rustfs-env.path;
      RemainAfterExit = true;
    };
    script = ''
      # Image era (0091): the serving image carries node + scripts/, so
      # the bootstrap runs there — no dev image, no node_modules volume.
      ${pkgs.podman}/bin/podman run --rm \
        --network sweatshop-harness \
        --env RUSTFS_ACCESS_KEY --env RUSTFS_SECRET_KEY \
        --volume /etc/sweatshop/rustfs-bucket-init.mjs:/app/rustfs-bucket-init.mjs:ro \
        10.10.0.6:5000/sweatshop/app:main \
        node rustfs-bucket-init.mjs
    '';
  };
}
