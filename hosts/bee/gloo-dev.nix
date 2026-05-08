# ── Gloo Dev Tooling on bee ────────────────────────────────────────
#
# Provides the tooling for Gloo devcontainer-based development:
#   - podman + docker-compose for running repo devcontainers
#   - glooctl CLI for up/down/start/stop/logs
#   - port publishing overrides per repo
#   - pi agent skill
#
# Each Gloo repo (polymer, gpl, hummingbird) has its own .devcontainer/.
# glooctl wraps docker-compose with port override files and manages
# dev servers as systemd user units (no blocking TUI).
#
# Enable with: services.gloo-dev.enable = true;
#
# Usage:
#   glooctl up polymer        # start devcontainer
#   glooctl start polymer     # start dev server (detached)
#   glooctl logs polymer -f   # follow logs
#   glooctl shell polymer     # interactive shell

{ config, lib, pkgs, ... }:

let
  cfg = config.services.gloo-dev;
  user = cfg.user;

  # glooctl with required tools on PATH
  glooctlPath = lib.makeBinPath [
    pkgs.docker-compose
    pkgs.podman
    pkgs.systemd
    pkgs.coreutils
    pkgs.gnugrep
    pkgs.gnused
    pkgs.bash
    pkgs.jq
  ];

  glooctl = pkgs.writeShellScriptBin "glooctl" ''
    export PATH="${glooctlPath}:$PATH"
    exec ${pkgs.bash}/bin/bash ${./gloo/glooctl} "$@"
  '';
in
{
  options.services.gloo-dev = {
    enable = lib.mkEnableOption "Gloo dev tooling (devcontainers + glooctl)";

    user = lib.mkOption {
      type = lib.types.str;
      default = "crussell";
      description = "User account for Gloo development";
    };
  };

  config = lib.mkIf cfg.enable {
    # ── System packages ───────────────────────────────────────────
    environment.systemPackages = with pkgs; [
      podman
      docker-compose
      glooctl
      jq
      git
      tmux
      socat
    ];

    # ── Podman (rootless) ─────────────────────────────────────────
    virtualisation.podman = {
      enable = true;
      dockerCompat = true;
    };

    # ── User linger (podman socket + systemd --user at boot) ─────
    system.activationScripts.gloo-dev-linger = lib.stringAfter [ "users" ] ''
      ${pkgs.systemd}/bin/loginctl enable-linger ${user} 2>/dev/null || true
    '';

    # ── Port publishing overrides ─────────────────────────────────
    # These docker-compose override files add port publishing for app
    # containers that the repo's .devcontainer/ doesn't publish.
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

    # ── Pi agent skill ────────────────────────────────────────────
    system.activationScripts.gloo-dev-skill = lib.stringAfter [ "users" ] ''
      SKILL_DIR="/home/${user}/.pi/agent/skills/gloo-dev"
      mkdir -p "$SKILL_DIR"
      cp ${./gloo/SKILL.md} "$SKILL_DIR/SKILL.md"
      chown -R ${user}:users "$SKILL_DIR"
    '';
  };
}
