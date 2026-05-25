# ── pi Coding Agent ──────────────────────────────────────────────────
#
# Colocates the pi-coding-agent package with its required
# OPENROUTER_API_KEY environment variable.  Any host that imports
# this module gets both — no partial config possible.
#
# Usage (in a host configuration.nix):
#   services.pi-agent.enable = true;
#
# The API key is available via:
#   - Interactive shells (zsh init)
#   - The env file at config.age.secrets.openrouter-api-key.path
#     for systemd EnvironmentFile= directives

{ config, lib, pkgs, unstable, ... }:

let
  cfg = config.services.pi-agent;
in
{
  options.services.pi-agent = {
    enable = lib.mkEnableOption "pi coding agent (package + OPENROUTER_API_KEY)";
  };

  config = lib.mkIf cfg.enable {
    # ── Package ────────────────────────────────────────────────────
    environment.systemPackages = [
      unstable."pi-coding-agent"
    ];

    # ── Extensions (installed to /etc/pi-extensions) ────────────────
    # Source files live in modules/pi-extensions/.  We stage them via
    # environment.etc then symlink into each user's ~/.pi tree via
    # tmpfiles so pi auto-discovers them.
    environment.etc = {
      "pi-extensions/ask/index.ts".source = ./pi-extensions/ask/index.ts;
      "pi-extensions/searxng-search/index.ts".source = ./pi-extensions/searxng-search/index.ts;
    };

    systemd.tmpfiles.rules = [
      "d /home/crussell/.pi/agent/extensions/ask 0755 crussell users -"
      "L+ /home/crussell/.pi/agent/extensions/ask/index.ts - - - /etc/pi-extensions/ask/index.ts"
      "d /home/crussell/.pi/agent/extensions/searxng-search 0755 crussell users -"
      "L+ /home/crussell/.pi/agent/extensions/searxng-search/index.ts - - - /etc/pi-extensions/searxng-search/index.ts"
    ];

    # ── Secret ─────────────────────────────────────────────────────
    age.secrets.openrouter-api-key = {
      file = ../secrets/openrouter-api-key.age;
      mode = "0440";
      group = "users";
    };

    # ── Shell environment ──────────────────────────────────────────
    # Exported in every interactive shell so pi can use it directly.
    programs.zsh.interactiveShellInit = ''
      export OPENROUTER_API_KEY="$(cat ${config.age.secrets.openrouter-api-key.path})"
    '';
  };
}
