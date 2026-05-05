# ── Date Night Restaurant Picker ─────────────────────────────────
#
# Native NixOS Python/Flask service.
# Migrated from hub's custom Podman container.
# Data: /var/lib/datenight/restaurants.json (migrate via rsync)

{ config, lib, pkgs, ... }:

let
  # Python environment with Flask
  pythonEnv = pkgs.python3.withPackages (ps: [ ps.flask ]);

  # App source in the Nix store
  datenightSrc = pkgs.stdenv.mkDerivation {
    name = "datenight-src";
    src = ./datenight;
    installPhase = ''
      mkdir -p $out
      cp -r . $out/
    '';
  };
in
{
  # ── Systemd service ─────────────────────────────────────────────
  systemd.services.datenight = {
    description = "Date Night Restaurant Picker";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      ExecStart = "${pythonEnv}/bin/python ${datenightSrc}/app.py";
      Environment = "DATA_FILE=/var/lib/datenight/restaurants.json";
      WorkingDirectory = "${datenightSrc}";
      StateDirectory = "datenight";
      StateDirectoryMode = "0750";
      DynamicUser = true;
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  # Caddy on hub proxies to this port
  networking.firewall.allowedTCPPorts = [ 7890 ];
}
