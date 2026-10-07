# ── bee: sweatshop (rootless quadlet, crussell) ───────────────────────
#
# Chad's personal software factory (repo: git.crussell.io/chad/sweatshop,
# checkout ~/ss/sweatshop). ONE instance, no dev server (sweatshop 0020):
# this unit serves `next start` of a production build in the checkout,
# and the checkout moves only through its own scripts/deploy.sh (stop →
# npm ci + next build + db:migrate → start). Sweatshop changes itself by
# PRs from its sandboxes; dsh is the emergency path if a deploy breaks it.
#
# Mechanics as hindsight.nix (D-017): materialize the quadlet files
# read-only under /etc, symlink into crussell's user quadlet search path,
# reload the user manager, enable.
#
# State lives in ~/ss/sweatshop/data (sqlite + WAL, the Workflow SDK local
# world, backups/) — in bee's restic paths (backup.nix). The nightly timer
# below writes a guaranteed-consistent copy, data/backups/nightly.db, an
# hour before the 00:00 (+≤1 h jitter) restic window.
#
# Ingress: http://bee:3300 directly (LAN/Nebula, no auth — sweatshop's hard
# rule: a real verifier before any internet exposure). Previews:
# bees Caddy pv-*.internal.crussell.io → 10.10.0.12:3301
# (hosts/bees/caddy/routes/internal/previews.caddy).
{ config, lib, pkgs, ... }:

let
  checkout = "/home/crussell/ss/sweatshop";
  units = [ "sweatshop.container" "sweatshop-harness.network" ];
in {
  environment.etc = lib.listToAttrs (map (u: {
    name = "sweatshop/${u}";
    value = {
      source = ./sweatshop + "/${u}";
      mode = "0444";
    };
  }) units);

  system.activationScripts.sweatshop-quadlet =
    lib.stringAfter [ "users" "etc" ] ''
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
        # every later restart belongs to scripts/deploy.sh.
      fi
    '';

  # Consistent online copy of the app db (better-sqlite3 backup API, via the
  # repo's own script in a one-off container with the app's mounts).
  systemd.user.services.sweatshop-db-snapshot = {
    description = "sweatshop nightly db snapshot (data/backups/nightly.db)";
    onFailure = [ "ntfy-failure@sweatshop-db-snapshot.service" ];
    unitConfig = {
      ConditionUser = "crussell";
      ConditionPathExists = "${checkout}/data/sweatshop.db";
    };
    path = [ pkgs.podman pkgs.bash pkgs.coreutils ];
    serviceConfig = {
      Type = "oneshot";
      WorkingDirectory = checkout;
      ExecStart =
        "${pkgs.bash}/bin/bash ${checkout}/dev exec -- node scripts/db-snapshot.mjs nightly";
    };
  };

  systemd.user.timers.sweatshop-db-snapshot = {
    wantedBy = [ "default.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 23:00";
      Persistent = true;
    };
  };
}
