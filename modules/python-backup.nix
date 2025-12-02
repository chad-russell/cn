{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.pythonContainerBackup;
  backupScript = "/home/crussell/docker/backup.py"; # Assuming standard location or configured path
  configFile = "/home/crussell/docker/backup-config.json";
in {
  options.services.pythonContainerBackup = {
    enable = mkEnableOption "Automated container backups using Python script";
    
    schedule = mkOption {
      type = types.str;
      default = "03:00:00";
      description = "Systemd calendar expression for when to run the backup.";
    };

    scriptPath = mkOption {
      type = types.str;
      default = backupScript;
      description = "Path to the backup.py script.";
    };

    configPath = mkOption {
      type = types.str;
      default = configFile;
      description = "Path to the backup-config.json file.";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.python-container-backup = {
      description = "Run Python Container Backup Script";
      path = with pkgs; [ python3 docker utillinux ]; # utillinux for mount
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = "${pkgs.python3}/bin/python3 ${cfg.scriptPath} --config ${cfg.configPath}";
      };
    };

    systemd.timers.python-container-backup = {
      description = "Timer for Python Container Backup Script";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.schedule;
        Persistent = true;
        Unit = "python-container-backup.service";
      };
    };
  };
}
