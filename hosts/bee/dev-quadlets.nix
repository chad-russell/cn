# ── bee: Remote dev quadlet stacks (gpl, polymer, buildspace) ──────────
#
# Mirrors the thinkpad's rootless user-quadlet dev stacks (the "perfect" setup)
# but delivered NixOS-declaratively, so `nix run .#deploy -- bee` registers them
# with zero manual install step and no cn checkout required on bee.
#
# Each project ships as *.container / *.volume / *.network quadlet input files
# plus a dev-server.sh (PID 1 of the app container), all under
# hosts/bee/dev-quadlets/<project>/. This module:
#
#   1. Materializes those files read-only under /etc/dev-quadlets/<project>/
#      (environment.etc → symlinks into the nix store; ideal as :ro bind sources).
#   2. Symlinks the quadlet units into ~/.config/containers/systemd/ for crussell
#      (the rootless podman user-quadlet search path).
#   3. Reloads crussell's user systemd manager so the podman-system-generator
#      picks up the new/changed units.
#
# Access from the laptop is via the bees internal Caddy
# (*.internal.crussell.io → 10.10.0.12:<port> over Nebula); see
# hosts/bees/caddy/routes/internal/dev.caddy and the top-level README.
#
# Units have NO [Install] section, so nothing auto-starts on boot — stacks run
# only on demand via `systemctl --user start <project>-dev-app` (or the `qd`
# wrapper this module ships). crussell has lingering enabled, so the user
# manager is always up and survives logout.

{ config, lib, pkgs, ... }:

let
  # Quadlet input files to install (project/basename). Order within a project
  # doesn't matter — the podman-system-generator resolves Requires/PartOf ties.
  quadletUnits = [
    # gpl
    "gpl/gpl-dev.network"
    "gpl/gpl-dev-db.volume"
    "gpl/gpl-dev-minio.volume"
    "gpl/gpl-dev-db.container"
    "gpl/gpl-dev-minio.container"
    "gpl/gpl-dev-app.container"
    # polymer
    "polymer/polymer-dev.network"
    "polymer/polymer-dev-db.volume"
    "polymer/polymer-dev-minio.volume"
    "polymer/polymer-dev-db.container"
    "polymer/polymer-dev-minio.container"
    "polymer/polymer-dev-app.container"
    # buildspace
    "buildspace/buildspace-dev.network"
    "buildspace/buildspace-dev-db.volume"
    "buildspace/buildspace-dev-minio.volume"
    "buildspace/buildspace-dev-db.container"
    "buildspace/buildspace-dev-minio.container"
    "buildspace/buildspace-dev-app.container"
  ];

  # dev-server.sh for each project (bind-mount source, NOT a quadlet unit).
  devServers = [
    "gpl/dev-server.sh"
    "polymer/dev-server.sh"
    "buildspace/dev-server.sh"
  ];

  # Everything that goes under /etc/dev-quadlets/.
  etcFiles = quadletUnits ++ devServers;
in
{
  # 1. Materialize units + dev-server.sh read-only under /etc/dev-quadlets/.
  #    environment.etc creates /etc/dev-quadlets/<path> as a symlink into the
  #    nix store, which the containers bind-mount (units for the generator to
  #    read; dev-server.sh mounted :ro into the app container).
  environment.etc = lib.genAttrs etcFiles
    (path: { source = ./dev-quadlets/${path}; mode = "0444"; });

  # 2. Symlink the quadlet units into crussell's user quadlet search path and
  #    reload the user manager. Runs after users exist (we chown to crussell).
  #    Idempotent: ln -sfn re-points existing symlinks at the current nix path.
  system.activationScripts.dev-quadlets = lib.stringAfter [ "users" "etc" ] ''
    dest="/home/crussell/.config/containers/systemd"
    mkdir -p "$dest"
    chown crussell:users "$dest"
    ${lib.concatMapStringsSep "\n" (u: ''
      ln -sfn "/etc/dev-quadlets/${u}" "$dest/$(basename ${u})"
      chown -h crussell:users "$dest/$(basename ${u})"
    '') quadletUnits}

    # Reload crussell's user manager so podman-system-generator regenerates the
    # *.service units from the (possibly changed) quadlet inputs. Linger is on,
    # so the user manager is running; reach it via its runtime dir.
    uid="$(id -u crussell 2>/dev/null || true)"
    if [ -n "$uid" ] && [ -d "/run/user/$uid" ]; then
      runuser -u crussell -- env XDG_RUNTIME_DIR="/run/user/$uid" \
        systemctl --user daemon-reload 2>/dev/null || true
    fi
  '';

  # 3. `qd` convenience wrapper (sister to the per-project qd on the thinkpad,
  #    but one script for all three projects since bee has no cn checkout to
  #    hold per-project copies). Raw `systemctl --user` always works too.
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "qd" ''
      # qd <gpl|polymer|buildspace> <up|down|restart|status|logs>
      set -euo pipefail
      proj="''${1:-}"; cmd="''${2:-up}"
      case "$proj" in
        gpl|polymer|buildspace) svc="$proj-dev-app" ;;
        *) echo "usage: qd <gpl|polymer|buildspace> <up|down|restart|status|logs>" >&2; exit 1 ;;
      esac
      case "$cmd" in
        up)      systemctl --user start "$svc" ;;
        down)    systemctl --user stop "$svc" ;;
        restart) systemctl --user restart "$svc" ;;
        status)  systemctl --user status "$svc" "$proj-dev-db" "$proj-dev-minio" ;;
        logs)    journalctl --user -u "$svc" -f ;;
        *) echo "unknown command: $cmd (up|down|restart|status|logs)" >&2; exit 1 ;;
      esac
    '')
  ];
}
