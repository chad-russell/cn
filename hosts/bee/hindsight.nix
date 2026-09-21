# ── bee: hindsight (rootless quadlet, crussell) ───────────────────────
#
# Vectorize Hindsight agent-memory server (https://github.com/vectorize-io/
# hindsight): retain/recall/reflect API + built-in MCP endpoint per bank
# (http://10.10.0.12:8888/mcp/{bank}/) + control-plane UI (:9999, gated by
# HINDSIGHT_CP_ACCESS_KEY). Serves every coding agent's long-term memory
# (dsh via the official hindsight-coding-agents integration; Claude Code /
# Codex / opencode wired later).
#
# Mechanics copied from filebrowser.nix (D-017): materialize the quadlet
# read-only under /etc, symlink into crussell's user quadlet search path,
# reload the user manager, enable. Data lives in the named podman volume
# `hindsight-data` (embedded pg0 Postgres), which lands under
# ~/.local/share/containers/storage/volumes — already inside bee's restic
# backup path; the ~9 GB re-pullable image layers are excluded in backup.nix.
#
# External ingress: bees Caddy →
#   hindsight.internal.crussell.io    → 10.10.0.12:8888 (API + MCP)
#   hindsight-ui.internal.crussell.io → 10.10.0.12:9999 (UI, key-gated)
# (hosts/bees/caddy/routes/internal/hindsight.caddy)
{ config, lib, pkgs, ... }:

{
  # LLM key (OpenRouter GLM flash) + UI access key. Owner crussell so the
  # rootless user quadlet can read it (proton-pass-env group-readable
  # precedent; /run/agenix is world-traversable, files are not).
  age.secrets.hindsight-env = {
    file = ../../secrets/hindsight-env.age;
    owner = "crussell";
    mode = "0400";
  };

  environment.etc."hindsight/hindsight.container" = {
    source = ./hindsight/hindsight.container;
    mode = "0444";
  };

  system.activationScripts.hindsight-quadlet =
    lib.stringAfter [ "users" "etc" ] ''
      dest="/home/crussell/.config/containers/systemd"
      mkdir -p "$dest"
      chown crussell:users "$dest"
      ln -sfn "/etc/hindsight/hindsight.container" "$dest/hindsight.container"
      chown -h crussell:users "$dest/hindsight.container"

      uid="$(id -u crussell 2>/dev/null || true)"
      if [ -n "$uid" ] && [ -d "/run/user/$uid" ]; then
        runuser -u crussell -- env XDG_RUNTIME_DIR="/run/user/$uid" \
          systemctl --user daemon-reload 2>/dev/null || true
        # enable is idempotent; generator only runs on daemon-reload, so
        # enable may no-op the very first boot until the next reload —
        # acceptable (container starts on the next activation).
        runuser -u crussell -- env XDG_RUNTIME_DIR="/run/user/$uid" \
          systemctl --user enable hindsight.service 2>/dev/null || true
      fi
    '';
}
