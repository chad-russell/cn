{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.containerBackup;

  # Define the options for the backup service
  jobOptions = { name, ... }: {
    options = {
      containerName = mkOption {
        type = types.str;
        description = "Name of the docker container to stop/start.";
      };
      volumes = mkOption {
        type = types.listOf types.str;
        description = "List of docker volumes to backup.";
      };
      keepDays = mkOption {
        type = types.int;
        default = 7;
        description = "Number of days to keep backups.";
      };
      serviceName = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Systemd service name to stop/start (optional, overrides containerName for stop/start).";
      };
    };
  };

in {
  options.services.containerBackup = {
    enable = mkEnableOption "Automated container backups to NFS";

    nfsServer = mkOption {
      type = types.str;
      default = "192.168.20.31";
      description = "NFS server IP address.";
    };

    nfsPath = mkOption {
      type = types.str;
      default = "/mnt/tank/backups";
      description = "NFS share path.";
    };

    mountPoint = mkOption {
      type = types.str;
      default = "/mnt/backups";
      description = "Local mount point for the NFS share.";
    };

    backend = mkOption {
      type = types.enum [ "docker" "podman" ];
      default = "docker";
      description = "Container backend to use (docker or podman).";
    };

    jobs = mkOption {
      type = types.attrsOf (types.submodule jobOptions);
      default = {};
      description = "Backup jobs configuration.";
    };
  };

  config = mkIf cfg.enable {
    # 1. Mount the NFS share
    fileSystems."${cfg.mountPoint}" = {
      device = "${cfg.nfsServer}:${cfg.nfsPath}";
      fsType = "nfs";
      options = [ 
        "x-systemd.automount" 
        "noauto" 
        "timeo=14" 
        "nfsvers=4"
        "rw"
        "soft"
        "intr"
      ];
    };

    # 2. Create the backup script and systemd service for each job
    systemd.services = mapAttrs' (name: job: nameValuePair "container-backup-${name}" {
      description = "Backup service for container ${job.containerName}";
      requires = if cfg.backend == "docker" then [ "docker.service" ] else [];
      after = [ "network.target" "remote-fs.target" ] ++ (if cfg.backend == "docker" then [ "docker.service" ] else []);
      # Only run when explicitly triggered (by timer or manually), not during system activation
      unitConfig = {
        ConditionPathExists = cfg.mountPoint;
        RefuseManualStart = false;
        RefuseManualStop = false;
      };
      # Don't want these services to auto-start on boot or during system activation
      wantedBy = lib.mkForce [];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        # Increase timeout for stopping services
        TimeoutStartSec = "5min";
      };
      path = with pkgs; [ (if cfg.backend == "docker" then docker else podman) gzip gnutar coreutils findutils systemd ];
      script = let
        stopCommand = if job.serviceName != null then ''
          echo "Stopping service ${job.serviceName}..."
          if systemctl is-active --quiet "${job.serviceName}"; then
            if ! systemctl stop "${job.serviceName}"; then
              echo "Warning: Failed to stop service ${job.serviceName}, continuing anyway..." >&2
            fi
            # Wait for service to fully stop
            for i in {1..30}; do
              if ! systemctl is-active --quiet "${job.serviceName}"; then
                break
              fi
              echo "Waiting for ${job.serviceName} to stop (attempt $i/30)..."
              sleep 1
            done
          else
            echo "Service ${job.serviceName} is not active, skipping stop."
          fi
        '' else ''
          echo "Stopping container ${job.containerName}..."
          if $BIN ps --filter "name=${job.containerName}" --filter "status=running" --format "{{.Names}}" | grep -q "${job.containerName}"; then
            if ! $BIN stop "${job.containerName}" 2>/dev/null; then
              echo "Warning: Failed to stop container ${job.containerName}, continuing anyway..." >&2
            fi
          else
            echo "Container ${job.containerName} is not running, skipping stop."
          fi
        '';
        
        startCommand = if job.serviceName != null then ''
          echo "Starting service ${job.serviceName}..."
          # Reset failed state if present
          systemctl reset-failed "${job.serviceName}" 2>/dev/null || true
          
          if ! systemctl start "${job.serviceName}"; then
            echo "Error: Failed to start service ${job.serviceName}" >&2
            exit 1
          fi
          
          # Wait for service to be active
          for i in {1..30}; do
            if systemctl is-active --quiet "${job.serviceName}"; then
              echo "Service ${job.serviceName} started successfully."
              break
            fi
            if [ $i -eq 30 ]; then
              echo "Error: Service ${job.serviceName} did not become active after 30 seconds" >&2
              exit 1
            fi
            echo "Waiting for ${job.serviceName} to start (attempt $i/30)..."
            sleep 1
          done
        '' else ''
          echo "Starting container ${job.containerName}..."
          if ! $BIN start "${job.containerName}" 2>/dev/null; then
            echo "Error: Failed to start container ${job.containerName}" >&2
            exit 1
          fi
        '';
      in ''
        set -euo pipefail
        
        BACKUP_DIR="${cfg.mountPoint}/containers/${name}"
        TIMESTAMP=$(date +%Y%m%d-%H%M%S)
        BIN="${cfg.backend}"
        mkdir -p "$BACKUP_DIR"

        echo "Starting backup for ${name} using $BIN..."

        # Stop the container/service
        ${stopCommand}

        # Backup volumes
        for vol in ${toString job.volumes}; do
          echo "Backing up volume $vol..."
          # Use a temporary alpine container to tar the volume
          # We mount the volume to /data and the backup dir to /backup
          $BIN run --rm \
            -v "$vol":/data:ro \
            -v "$BACKUP_DIR":/backup \
            alpine:latest \
            tar czf "/backup/$TIMESTAMP-$vol.tar.gz" -C /data .
        done

        # Start the container/service
        ${startCommand}

        # Prune old backups
        echo "Pruning backups older than ${toString job.keepDays} days..."
        find "$BACKUP_DIR" -name "*.tar.gz" -mtime +${toString job.keepDays} -delete
        
        echo "Backup for ${name} completed successfully."
      '';
    }) cfg.jobs;

    # 3. Create a timer to trigger the backups
    # For simplicity, we'll create one timer that triggers all backup services, 
    # OR we can just rely on the services being triggered individually if we want different schedules.
    # The plan said "daily (e.g., at 3 AM)". Let's make a target that runs them all.
    
    systemd.targets.container-backup = {
      description = "Target to run all container backups";
      wants = map (name: "container-backup-${name}.service") (attrNames cfg.jobs);
    };

    systemd.timers.container-backup = {
      description = "Daily container backup timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "03:00:00";
        Persistent = true;
        Unit = "container-backup.target";
      };
    };
  };
}
