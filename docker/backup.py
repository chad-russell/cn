#!/usr/bin/env python3
import json
import subprocess
import datetime
import os
import sys
import time
import argparse
from pathlib import Path

CONFIG_FILE = "backup-config.json"

def log(message):
    print(f"[{datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {message}")

def run_command(command, shell=False, check=True):
    try:
        subprocess.run(command, shell=shell, check=check, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        return True
    except subprocess.CalledProcessError as e:
        log(f"Error running command: {command if isinstance(command, str) else ' '.join(command)}")
        log(f"Error output: {e.stderr}")
        return False

def ensure_mount(nfs_config):
    mount_point = nfs_config.get("mountPoint", "/mnt/backups")
    server = nfs_config["server"]
    path = nfs_config["path"]
    
    # Check if mounted
    if os.path.ismount(mount_point):
        return True

    log(f"Mounting {server}:{path} to {mount_point}...")
    os.makedirs(mount_point, exist_ok=True)
    
    cmd = [
        "mount", "-t", "nfs", 
        "-o", "rw,soft,intr,timeo=14,nfsvers=4",
        f"{server}:{path}", 
        mount_point
    ]
    
    if run_command(cmd):
        log("Mount successful.")
        return True
    else:
        log("Failed to mount NFS share.")
        return False

def backup_job(job, defaults, mount_point):
    name = job["name"]
    container_name = job.get("containerName", name)
    backend = job.get("backend", defaults.get("backend", "docker"))
    keep_days = job.get("keepDays", defaults.get("keepDays", 7))
    volumes = job.get("volumes", [])
    service_name = job.get("serviceName")

    backup_dir = os.path.join(mount_point, "containers", name)
    timestamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    
    log(f"Starting backup for job: {name}")
    os.makedirs(backup_dir, exist_ok=True)

    try:
        # Stop container/service
        if service_name:
            log(f"Stopping service {service_name}...")
            if not run_command(["systemctl", "stop", service_name], check=False):
                log(f"Warning: Failed to stop service {service_name}, proceeding anyway...")
        else:
            log(f"Stopping container {container_name}...")
            if not run_command([backend, "stop", container_name], check=False):
                log(f"Warning: Failed to stop container {container_name}, proceeding anyway...")

        # Backup volumes
        for vol in volumes:
            log(f"Backing up volume {vol}...")
            target_file = os.path.join(backup_dir, f"{timestamp}-{vol}.tar.gz")
            
            # Using temporary alpine container to tar volume
            # Corresponds to: $BIN run --rm -v "$vol":/data:ro -v "$BACKUP_DIR":/backup alpine:latest tar czf ...
            docker_cmd = [
                backend, "run", "--rm",
                "-v", f"{vol}:/data:ro",
                "-v", f"{backup_dir}:/backup",
                "alpine:latest",
                "tar", "czf", f"/backup/{os.path.basename(target_file)}", "-C", "/data", "."
            ]
            
            if not run_command(docker_cmd):
                log(f"Failed to backup volume {vol}")
                # We continue to try other volumes even if one fails
            else:
                log(f"Volume {vol} backed up successfully.")

    except Exception as e:
        log(f"Exception during backup of {name}: {e}")
    finally:
        # Restart container/service
        if service_name:
            log(f"Starting service {service_name}...")
            run_command(["systemctl", "start", service_name], check=False)
        else:
            log(f"Starting container {container_name}...")
            run_command([backend, "start", container_name], check=False)

    # Prune old backups
    log(f"Pruning backups older than {keep_days} days for {name}...")
    try:
        # find "$BACKUP_DIR" -name "*.tar.gz" -mtime +${toString job.keepDays} -delete
        # Using python generic approach or subprocess find
        run_command(["find", backup_dir, "-name", "*.tar.gz", "-mtime", f"+{keep_days}", "-delete"])
    except Exception as e:
        log(f"Error pruning backups: {e}")

    log(f"Finished job: {name}")

def main():
    parser = argparse.ArgumentParser(description="Backup containers.")
    parser.add_argument("--config", "-c", default=CONFIG_FILE, help=f"Path to configuration file (default: {CONFIG_FILE})")
    args = parser.parse_args()

    if not os.path.exists(args.config):
        log(f"Config file not found at {args.config}")
        sys.exit(1)

    with open(args.config, 'r') as f:
        config = json.load(f)

    nfs_config = config.get("nfs", {})
    if not ensure_mount(nfs_config):
        log("Aborting backups because NFS mount failed.")
        sys.exit(1)

    mount_point = nfs_config.get("mountPoint", "/mnt/backups")
    defaults = config.get("defaults", {})
    jobs = config.get("jobs", [])

    success_count = 0
    fail_count = 0

    for job in jobs:
        try:
            backup_job(job, defaults, mount_point)
            success_count += 1
        except Exception as e:
            log(f"CRITICAL ERROR in job {job.get('name', 'unknown')}: {e}")
            fail_count += 1

    log(f"All jobs completed. Success: {success_count}, Failures: {fail_count}")

if __name__ == "__main__":
    if os.geteuid() != 0:
        log("This script must be run as root (for docker/mount permissions).")
        sys.exit(1)
    main()
