# ── bee: tansweat (rootless quadlet, crussell) ────────────────────────
#
# Chad's next-gen sweatshop replacement (repo git.crussell.io/chad/
# tansweat). Serves apps/web on 10.10.0.12:3330 →
# https://tansweat.internal.crussell.io (bees Caddy, no auth: LAN/Nebula
# only — never route publicly).
#
# GitOps flow: merge to tansweat main → bees runner builds the image →
# zot 10.10.0.6:5000/tansweat/app:main → ssh bee: pull + `systemctl
# --user restart tansweat.service`. This module only installs the quadlet
# (mechanics as sweatshop.nix / tastyquant.nix: read-only under /etc,
# symlinked into crussell's user quadlet path, user manager reloaded).
# Activation never starts or restarts the app; CI and the nightly
# podman-auto-update (AutoUpdate=registry) own restarts.
#
# State: ~/tansweat-data (db + WAL, keys, claude-home, codex-home) — in
# restic paths (backup.nix). The timer below writes a consistent copy,
# backups/nightly.db, before the nightly restic window.
{ config, lib, pkgs, ... }:

let
  image = "10.10.0.6:5000/tansweat/app:main";
  dataDir = "/home/crussell/tansweat-data";
  # node:sqlite online backup of the live db (WAL-safe), run in a one-off
  # container of the app's own image (node is baked in).
  backupScript = ''
    const { DatabaseSync } = require("node:sqlite");
    const fs = require("node:fs");
    fs.mkdirSync("/data/backups", { recursive: true });
    const db = new DatabaseSync("/data/tansweat.db");
    db.backup("/data/backups/nightly.db")
      .then(() => { db.close(); })
      .catch((e) => { console.error(e); process.exit(1); });
  '';
in {
  environment.etc."tansweat/tansweat.container" = {
    source = ./tansweat/tansweat.container;
    mode = "0444";
  };

  system.activationScripts.tansweat-quadlet =
    lib.stringAfter [ "users" "etc" ] ''
      dest="/home/crussell/.config/containers/systemd"
      mkdir -p "$dest"
      chown crussell:users "$dest"
      ln -sfn /etc/tansweat/tansweat.container "$dest/tansweat.container"
      chown -h crussell:users "$dest/tansweat.container"

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

  systemd.user.services.tansweat-db-snapshot = {
    description = "tansweat nightly db snapshot (backups/nightly.db)";
    onFailure = [ "ntfy-failure@tansweat-db-snapshot.service" ];
    unitConfig = {
      ConditionUser = "crussell";
      ConditionPathExists = "${dataDir}/tansweat.db";
    };
    serviceConfig = {
      Type = "oneshot";
      ExecStart = ''
        ${pkgs.podman}/bin/podman run --rm --network host \
          -v ${dataDir}:/data ${image} \
          node -e '${backupScript}'
      '';
    };
  };

  systemd.user.timers.tansweat-db-snapshot = {
    wantedBy = [ "default.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 23:05";
      Persistent = true;
    };
  };
}
