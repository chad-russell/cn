# ── bee: ninerouter (rootless quadlet, crussell) ──────────────────────
#
# 9router (https://github.com/decolua/9router) — AI provider gateway:
# one OpenAI-compatible endpoint (http://10.10.0.12:20128/v1) + dashboard
# (:20128/dashboard) fronting OAuth subscription providers (Cursor cu/*,
# OpenAI Codex cx/*), API-key providers (OpenRouter, GLM, DeepSeek …) and
# free tiers, with auto token refresh and quota tracking. The household
# provider hub: dsh (and any future AI project) points here instead of
# configuring N providers everywhere.
#
# Mechanics copied from hindsight.nix (filebrowser D-017 lineage):
# materialize the quadlet read-only under /etc, symlink into crussell's
# user quadlet search path, reload the user manager, enable. Data lives
# in the named podman volume `ninerouter-data` (SQLite), which lands
# under ~/.local/share/containers/storage/volumes — already inside bee's
# restic backup path; image layers are excluded in backup.nix.
#
# External ingress: bees Caddy → 9router.internal.crussell.io
# → 10.10.0.12:20128 (hosts/bees/caddy/routes/internal/ninerouter.caddy).
# Dashboard login needs that HTTPS route (AUTH_COOKIE_SECURE=true); the
# API uses Bearer keys and answers on either path.
{ config, lib, pkgs, ... }:

{
  # JWT_SECRET + INITIAL_PASSWORD + API_KEY_SECRET + MACHINE_ID_SALT —
  # all random at creation (upstream defaults are weak/public). Owner
  # crussell so the rootless user quadlet can read it (hindsight-env
  # precedent; /run/agenix is world-traversable, files are not).
  age.secrets.ninerouter-env = {
    file = ../../secrets/ninerouter-env.age;
    owner = "crussell";
    mode = "0400";
  };

  environment.etc."ninerouter/ninerouter.container" = {
    source = ./ninerouter/ninerouter.container;
    mode = "0444";
  };

  system.activationScripts.ninerouter-quadlet =
    lib.stringAfter [ "users" "etc" ] ''
      dest="/home/crussell/.config/containers/systemd"
      mkdir -p "$dest"
      chown crussell:users "$dest"
      ln -sfn "/etc/ninerouter/ninerouter.container" "$dest/ninerouter.container"
      chown -h crussell:users "$dest/ninerouter.container"

      uid="$(id -u crussell 2>/dev/null || true)"
      if [ -n "$uid" ] && [ -d "/run/user/$uid" ]; then
        runuser -u crussell -- env XDG_RUNTIME_DIR="/run/user/$uid" \
          systemctl --user daemon-reload 2>/dev/null || true
        # enable is idempotent; generator only runs on daemon-reload, so
        # enable may no-op the very first boot until the next reload —
        # acceptable (container starts on the next activation).
        runuser -u crussell -- env XDG_RUNTIME_DIR="/run/user/$uid" \
          systemctl --user enable ninerouter.service 2>/dev/null || true
      fi
    '';
}
