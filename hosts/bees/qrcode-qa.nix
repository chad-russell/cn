# ── QRCode.Bible Migration QA ──────────────────────────────────────

{ pkgs, ... }:

let
  pythonEnv = pkgs.python3.withPackages (ps: [ ps.flask ps.gunicorn ]);
  qrcodeQaSrc = pkgs.stdenv.mkDerivation {
    name = "qrcode-qa-src";
    src = ./qrcode-qa;
    installPhase = ''
      mkdir -p $out
      cp -r . $out/
    '';
  };
in {
  systemd.services.qrcode-qa = {
    description = "QRCode.Bible crowd-sourced migration QA";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      ExecStart =
        "${pythonEnv}/bin/gunicorn --bind 10.10.0.6:7891 --workers 2 --threads 4 --access-logfile - app:app";
      Environment = [
        "DATABASE=/var/lib/qrcode-qa/qa.sqlite3"
        "PAGES_FILE=${qrcodeQaSrc}/pages.json"
        "OLD_BASE_URL=https://www.qrcode.bible"
        "NEW_BASE_URL=https://qr-dev.qrcode.bible"
      ];
      WorkingDirectory = qrcodeQaSrc;
      StateDirectory = "qrcode-qa";
      StateDirectoryMode = "0750";
      DynamicUser = true;
      Restart = "on-failure";
      RestartSec = 5;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      LockPersonality = true;
      RestrictSUIDSGID = true;
      SystemCallArchitectures = "native";
    };
  };
}
