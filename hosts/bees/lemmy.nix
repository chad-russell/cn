# ── Lemmy (bees) ────────────────────────────────────────────────────
#
# Private Lemmy instance at lemmy.internal.crussell.io — stood up
# 2026-09-10 as the substrate for glen's transport #4 experiment (the
# reddit-style agent surface; see glen: research/design/channel-3-4-
# candidates.md). Native nixpkgs services.lemmy module (cn's preferred
# pattern), no nginx/caddy exposure from the module itself — the
# containerized Caddy fronts it via routes/internal/lemmy.caddy.
#
# Topology (all loopback; nothing new in the firewall):
#   lemmy-server  127.0.0.1:8536   REST/WS backend
#   lemmy-ui      127.0.0.1:1234   SSR frontend
#   pict-rs       127.0.0.1:8537   image store (module default 8080
#                                  would collide with qBittorrent's
#                                  Web UI on bees)
#   postgres      the existing bees cluster via /run/postgresql (the
#                  immich DB lives there too; ensure* lists merge)
#
# Privacy posture (Chad 2026-09-10): private instance, registration
# closed, no federation. In lemmy 0.19.x these are NOT config.hjson
# keys — they are database columns, and the nixpkgs module even asserts
# against settings.federation. They are applied once, post-setup, via
# SQL (idempotent), then owned by the admin UI:
#
#   sudo -u postgres psql lemmy \
#     -c "UPDATE local_site SET registration_mode = 'closed';" \
#     -c "UPDATE site SET private_instance = true;"
#
# (enum registration_mode_enum: 'closed' | 'require_application' |
#  'open'. private_instance auth-gates all listing endpoints and stops
#  federation traffic; the *.internal wildcard also resolves only to
#  the Nebula overlay, so remote servers can't reach us regardless.)
#
# First boot: settings.setup seeds the admin (chad) from the agenix'd
# password (secrets/lemmy-admin-password.age) — no web wizard.
# Verify after deploy:
#   curl -f https://lemmy.internal.crussell.io/nodeinfo/2.0.json
#
# Bot user (future, glen transport #4): registration is closed, so a
# bot account needs either a temporary registration_mode flip or direct
# local_user seeding — deliberately not improvised here.

{ config, lib, pkgs, ... }:

{
  age.secrets.lemmy-admin-password.file =
    ../../secrets/lemmy-admin-password.age;

  services.pict-rs = {
    # Enabled by the lemmy module anyway; kept explicit for the port
    # override below, which lemmy's pictrs.url picks up automatically.
    enable = true;
    port = 8537;
  };

  services.lemmy = {
    enable = true;
    database.createLocally = true;
    adminPasswordFile = config.age.secrets.lemmy-admin-password.path;

    settings = {
      hostname = "lemmy.internal.crussell.io";
      # bind/port stay at module defaults (127.0.0.1:8536). tls_enabled
      # stays true (module default): lemmy builds https:// URLs for its
      # public hostname while serving plain http on loopback behind the
      # TLS-terminating proxy — same posture as lemmy-ansible + nginx.
      setup = {
        admin_username = "chad";
        site_name = "Crussell Hub";
        admin_email = "chad@crussell.io";
      };
      # Registration is closed via the DB posture above; no captcha to
      # solve. (0.19 may treat this as inert — kept for parity with the
      # module's own option set.)
      captcha.enabled = false;
    };
  };

  # The module hardcodes LEMMY_UI_HTTPS=false (plain-http edge); our
  # edge is the TLS-terminating Caddy, so the UI must generate https
  # links. lemmy-ansible sets the same for nginx TLS fronting.
  systemd.services.lemmy-ui.environment.LEMMY_UI_HTTPS = lib.mkForce "true";
}
