# ── gateway: Forgejo (git.crussell.io) ──────────────────────────────
#
# Self-hosted git forge — single-admin MVP (2026-09-08 plan).
#  - SQLite, no Postgres (single user; daily `forgejo dump` to stateDir/dump).
#  - HTTPS via the gateway Caddy (git.crussell.io → 127.0.0.1:3000).
#  - Git-over-SSH via Forgejo's BUILT-IN ssh server on :2222 — gateway's
#    real sshd keeps :22 (pubkey-only, fail2ban). Forgejo's internal SSH
#    server is public-key-only by design, no extra hardening needed.
#  - Registration disabled; Chad is the only account (TOTP 2FA is a UI step).
#  - No secrets on the VPS: INSTALL_LOCK + module-generated SECRET_KEY /
#    INTERNAL_TOKEN / JWT_SECRET live under /var/lib/forgejo (state, not config).
#
# State: /var/lib/forgejo (DB, repos, dumps). Backup story for MVP = the
# daily dump service below; fold into restic later if this grows.

{ config, lib, pkgs, ... }:

{
  services.forgejo = {
    enable = true;

    database.type = "sqlite3";

    # Daily `forgejo dump` (repos + db + config) into /var/lib/forgejo/dump,
    # default 4-week retention. Trivial single-user backup.
    dump.enable = true;

    settings = {
      DEFAULT.APP_NAME = "crussell forge";

      server = {
        DOMAIN = "git.crussell.io";
        ROOT_URL = "https://git.crussell.io/";
        HTTP_ADDR = "127.0.0.1"; # Caddy is the only HTTP client
        HTTP_PORT = 3000;

        # Built-in SSH server on a dedicated port (real sshd keeps :22).
        START_SSH_SERVER = true;
        SSH_LISTEN_PORT = 2222;
        SSH_PORT = 2222; # port shown in clone URLs
        # The built-in SSH server only accepts this username (defaults to
        # RUN_USER = "forgejo"). "git" gives the conventional git@ URLs.
        BUILTIN_SSH_SERVER_USER = "git";
      };

      service = {
        DISABLE_REGISTRATION = true;
        SHOW_REGISTRATION_BUTTON = false;
      };

      session.COOKIE_SECURE = true; # served over HTTPS only

      actions.ENABLED = true; # execution needs a runner (separate card)
      # Push to a nonexistent <user>/<repo>.git to create it. Lets CI jobs
      # clone cn (and future repos) over SSH without the admin API.
      repository.ENABLE_PUSH_CREATE_USER = true;
    };
  };

  # Git-over-SSH from the internet (public-key-only auth inside Forgejo).
  networking.firewall.allowedTCPPorts = [ 2222 ];
}
