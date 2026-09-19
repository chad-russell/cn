# ── bee: filebrowser (rootless quadlet, crussell) ─────────────────────
#
# Replaces the manually-started `podman run` container (2026-09-19,
# sprawl audit D-017): same image, port (Nebula 10.10.0.12:8093 → 8080),
# and mounts, but nix-managed and supervised (Restart=always).
#
# Mechanics copied from dev-quadlets.nix: materialize the quadlet
# read-only under /etc, symlink into crussell's user quadlet search path,
# reload the user manager so podman-system-generator picks it up — plus
# enable (it is wanted at boot, not on-demand). Data stays at
# ~/filebrowser/data (crussell-owned, migrated as-is from the manual
# container).
{ config, lib, pkgs, ... }:

{
  environment.etc."filebrowser/filebrowser.container" = {
    source = ./filebrowser/filebrowser.container;
    mode = "0444";
  };

  system.activationScripts.filebrowser-quadlet =
    lib.stringAfter [ "users" "etc" ] ''
      dest="/home/crussell/.config/containers/systemd"
      mkdir -p "$dest"
      chown crussell:users "$dest"
      ln -sfn "/etc/filebrowser/filebrowser.container" "$dest/filebrowser.container"
      chown -h crussell:users "$dest/filebrowser.container"

      uid="$(id -u crussell 2>/dev/null || true)"
      if [ -n "$uid" ] && [ -d "/run/user/$uid" ]; then
        runuser -u crussell -- env XDG_RUNTIME_DIR="/run/user/$uid" \
          systemctl --user daemon-reload 2>/dev/null || true
        # enable is idempotent; the generator only runs on daemon-reload,
        # so enable may no-op the very first boot until the next reload —
        # acceptable (container starts on the next activation).
        runuser -u crussell -- env XDG_RUNTIME_DIR="/run/user/$uid" \
          systemctl --user enable filebrowser.service 2>/dev/null || true
      fi
    '';
}
