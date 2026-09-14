# hosts/bee/artifacts.nix — static artifact host
#
# https://artifacts.internal.crussell.io — bees caddy terminates TLS
# (wildcard *.internal.crussell.io) and proxies to bee 10.10.0.12:8910
# (route: hosts/bees/caddy/routes/internal/artifacts.caddy).
#
# Serves ~/artifacts (restic-covered) + a tiny JSON API:
#   POST /-/delete, POST /-/reindex, GET /-/health
# consumed by the catalog page (~/artifacts/index.html) and the
# publish-artifact script (dsh skill: skills/artifacts).
#
# Replaces the hermes-era off-repo `python -m http.server` user unit
# (2026-09-07, ~/.config/systemd/user/artifacts-server.service — FBQ
# pattern) now that the catalog needs delete/reindex. The dsh skill
# `artifacts` documents the publishing workflow.
{ config, pkgs, ... }:
let
  serverPy = pkgs.writeText "artifacts-server.py" (builtins.readFile ./artifacts-server.py);
in
{
  systemd.services.artifacts-server = {
    description = "Static artifact host — ~/artifacts → artifacts.internal.crussell.io";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      User = "crussell";
      Group = "users";
      ExecStart = "${pkgs.python3}/bin/python3 ${serverPy} --bind 10.10.0.12 --port 8910 --root /home/crussell/artifacts";
      Restart = "on-failure";
      RestartSec = 3;
    };
  };
}
