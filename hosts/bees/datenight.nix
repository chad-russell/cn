# ── Date Night Restaurant Picker ─────────────────────────────────

{ config, lib, pkgs, ... }:

let
  pythonEnv = pkgs.python3.withPackages (ps: [ ps.flask ]);

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

}
