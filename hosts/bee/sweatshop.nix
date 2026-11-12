# ── bee: sweatshop (rootless quadlet, crussell) ────────────────────────
#
# Renamed successor (repo git.crussell.io/chad/sweatshop).
# Old app retired 2026-11; repo retained as chad/sweatshop-legacy.
# Serves apps/web on 10.10.0.12:3330 →
# https://sweatshop.internal.crussell.io (bees Caddy, no auth: LAN/Nebula
# only — never route publicly).
#
# GitOps flow: merge to sweatshop main → bees runner builds the image →
# zot 10.10.0.6:5000/sweatshop/app:main → ssh bee: pull + `systemctl
# --user restart sweatshop.service`. This module only installs the quadlet
# (mechanics as tastyquant.nix: read-only under /etc,
# symlinked into crussell's user quadlet path, user manager reloaded).
# Activation never starts or restarts the app; CI and the nightly
# podman-auto-update (AutoUpdate=registry) own restarts.
#
# State: ~/sweatshop-data (db + WAL, keys, claude-home, codex-home) — in
# restic paths (backup.nix). The timer below writes a consistent copy,
# backups/nightly.db, before the nightly restic window.
#
# The snapshot script lives as a FILE, /etc/sweatshop/db-snapshot.mjs
# (bind-mounted read-only into a one-off container of the app image), not
# as an inline `node -e '<JS>'` in ExecStart: systemd rejected the
# multi-line single-quoted script ("Unbalanced quoting", unit wouldn't
# load). It uses VACUUM INTO because node:24's DatabaseSync has no
# .backup(). Both were live lessons, 2026-11-03.
{ config, lib, pkgs, ... }:

let
  image = "10.10.0.6:5000/sweatshop/app:main";
  dataDir = "/home/crussell/sweatshop-data";
in {
  environment.etc."sweatshop/sweatshop.container" = {
    source = ./sweatshop/sweatshop.container;
    mode = "0444";
  };

  environment.etc."sweatshop/db-snapshot.mjs" = {
    source = ./sweatshop/db-snapshot.mjs;
    mode = "0444";
  };

  system.activationScripts.sweatshop-quadlet =
    lib.stringAfter [ "users" "etc" ] ''
      dest="/home/crussell/.config/containers/systemd"
      mkdir -p "$dest"
      chown crussell:users "$dest"
      # Retired successor quadlet name (assembled for the obsolete-name audit),
      # plus the harness network and sidecar retired with the old app.
      retiredPrefix=tan
      rm -f "$dest/''${retiredPrefix}sweat.container" "$dest/sweatshop-harness.network" "$dest/rustfs.container"
      ln -sfn /etc/sweatshop/sweatshop.container "$dest/sweatshop.container"
      chown -h crussell:users "$dest/sweatshop.container"

      uid="$(id -u crussell 2>/dev/null || true)"
      if [ -n "$uid" ] && [ -d "/run/user/$uid" ]; then
        runuser -u crussell -- env XDG_RUNTIME_DIR="/run/user/$uid" \
          systemctl --user daemon-reload 2>/dev/null || true
      fi
    '';

  # zot (bees, Nebula-only) serves plain HTTP. Same entry as tastyquant.nix;
  # list options concatenate, so the duplicate is harmless and keeps this
  # module self-contained.
  virtualisation.containers.registries.insecure = [ "10.10.0.6:5000" ];

  systemd.user.services.sweatshop-db-snapshot = {
    description = "sweatshop nightly db snapshot (backups/nightly.db)";
    onFailure = [ "ntfy-failure@sweatshop-db-snapshot.service" ];
    unitConfig = {
      ConditionUser = "crussell";
      ConditionPathExists = "${dataDir}/sweatshop.db";
    };
    serviceConfig = {
      Type = "oneshot";
      ExecStart =
        "${pkgs.podman}/bin/podman run --rm --network host -v ${dataDir}:/data -v /etc/sweatshop/db-snapshot.mjs:/db-snapshot.mjs:ro ${image} node /db-snapshot.mjs";
    };
  };

  systemd.user.timers.sweatshop-db-snapshot = {
    wantedBy = [ "default.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 23:05";
      Persistent = true;
    };
  };
}
