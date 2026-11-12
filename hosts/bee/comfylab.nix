# ── bee: comfylab (rootless quadlet, crussell) ─────────────────────────
#
# Mobile-first ComfyUI front-end (repo git.crussell.io/chad/comfylab).
# Serves 10.10.0.12:3350 → https://comfylab.internal.crussell.io (bees
# Caddy, no auth: LAN/Nebula only — never route publicly).
#
# GitOps flow: merge to comfylab main → bees runner builds the image →
# zot 10.10.0.6:5000/comfylab/app:main → ssh bee: pull + `systemctl
# --user restart comfylab.service`. This module only installs the quadlet
# (mechanics as sweatshop.nix: read-only under /etc, symlinked into
# crussell's user quadlet path, user manager reloaded). Activation never
# starts or restarts the app; CI and the nightly podman-auto-update
# (AutoUpdate=registry) own restarts.
#
# State: ~/comfylab-data (sqlite gallery, cached images, env/overrides.env,
# ssh/ key for the ComfyUI power button) — in restic paths (backup.nix).
{ config, lib, pkgs, ... }:

let dataDir = "/home/crussell/comfylab-data";
in {
  environment.etc."comfylab/comfylab.container" = {
    source = ./comfylab/comfylab.container;
    mode = "0444";
  };

  system.activationScripts.comfylab-quadlet =
    lib.stringAfter [ "users" "etc" ] ''
      dest="/home/crussell/.config/containers/systemd"
      mkdir -p "$dest"
      chown crussell:users "$dest"
      ln -sfn /etc/comfylab/comfylab.container "$dest/comfylab.container"
      chown -h crussell:users "$dest/comfylab.container"

      uid="$(id -u crussell 2>/dev/null || true)"
      if [ -n "$uid" ] && [ -d "/run/user/$uid" ]; then
        runuser -u crussell -- env XDG_RUNTIME_DIR="/run/user/$uid" \
          systemctl --user daemon-reload 2>/dev/null || true
      fi
    '';

  # State dir skeleton (owned by crussell; the container writes as crussell
  # via the rootless engine).
  system.activationScripts.comfylab-dirs = lib.stringAfter [ "users" ] ''
    mkdir -p ${dataDir}/env ${dataDir}/images ${dataDir}/ssh
    chown -R crussell:users ${dataDir}/env ${dataDir}/images ${dataDir}/ssh
    chmod 700 ${dataDir}/ssh
  '';

  # zot (bees, Nebula-only) serves plain HTTP. Same entry as sweatshop.nix;
  # list options concatenate, so the duplicate is harmless and keeps this
  # module self-contained.
  virtualisation.containers.registries.insecure = [ "10.10.0.6:5000" ];
}
