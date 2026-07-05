# ── Gloo Dev Support on bee ────────────────────────────────────────
#
# Minimal module: installs podman compose override files for the
# Gloo devcontainer workflow.
#
# Each Gloo repo (polymer, gpl, hummingbird) has its own .devcontainer/.
# You run them directly with podman compose — no wrappers, no systemd
# units, no glooctl.
#
# Override files add port publishing + rootless podman UID mapping fix.
# They are podman-specific and must NOT be committed to the product repos
# (breaks Docker Desktop on macOS).
#
# podman, docker-compose, and user linger are provided by buildspace.nix.
#
# Enable with: services.gloo-dev.enable = true;

{ config, lib, pkgs, ... }:

let
  cfg = config.services.gloo-dev;
  user = cfg.user;
in
{
  options.services.gloo-dev = {
    enable = lib.mkEnableOption "Gloo dev support (override files)";

    user = lib.mkOption {
      type = lib.types.str;
      default = "crussell";
      description = "User account for Gloo development";
    };
  };

  config = lib.mkIf cfg.enable {
    # ── Port publishing + podman UID overrides ────────────────────
    # These docker-compose override files add port publishing for app
    # containers (the repos rely on VS Code forwardPorts) and
    # userns_mode: "keep-id" for rootless podman UID mapping.
    system.activationScripts.gloo-dev-overrides = lib.stringAfter [ "users" ] ''
      mkdir -p /home/${user}/.config/gloo/overrides
      ${lib.concatStringsSep "\n" (map
        (name: ''
          cp ${./gloo/overrides/${name}.yml} /home/${user}/.config/gloo/overrides/${name}.yml
        '')
        [ "polymer" "hb" "gpl" ]
      )}
      chown -R ${user}:users /home/${user}/.config/gloo
    '';
  };
}
