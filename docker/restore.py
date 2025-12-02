#!/usr/bin/env python3
import json
import subprocess
import datetime
import os
import sys
import glob
import argparse

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

def find_backups(backup_dir, timestamp_prefix=None):
    """
    Finds backup files for a given directory.
    If timestamp_prefix is provided, filters by that prefix.
    Otherwise, finds the set of files with the latest timestamp.
    
    Returns a dictionary mapping volume_name -> backup_file_path
    """
    all_files = glob.glob(os.path.join(backup_dir, "*.tar.gz"))
    if not all_files:
        return None, "No backup files found in directory."

    # Group files by timestamp
    # Filename format: TIMESTAMP-volumename.tar.gz
    # Example: 20251201-191215-n8n-data.tar.gz
    
    backups_by_timestamp = {}
    
    for f in all_files:
        basename = os.path.basename(f)
        parts = basename.split("-", 2) # Split into [date, time, rest]
        if len(parts) < 3:
            continue
            
        ts = f"{parts[0]}-{parts[1]}" # e.g. 20251201-191215
        vol_part = parts[2]
        
        # Remove extension .tar.gz
        if vol_part.endswith(".tar.gz"):
            vol_name = vol_part[:-7]
        else:
            continue
            
        if ts not in backups_by_timestamp:
            backups_by_timestamp[ts] = {}
        
        backups_by_timestamp[ts][vol_name] = f

    if not backups_by_timestamp:
        return None, "No valid backup files parsed."

    selected_ts = None
    
    if timestamp_prefix:
        # Find exact match or partial match
        matches = [ts for ts in backups_by_timestamp.keys() if ts.startswith(timestamp_prefix)]
        if not matches:
            return None, f"No backups found matching prefix: {timestamp_prefix}"
        if len(matches) > 1:
            # If multiple matches (unlikely with full timestamp, but possible with partial), pick latest
            matches.sort(reverse=True)
            selected_ts = matches[0]
            log(f"Multiple backups match prefix '{timestamp_prefix}'. Selecting latest: {selected_ts}")
        else:
            selected_ts = matches[0]
    else:
        # Pick latest
        timestamps = sorted(backups_by_timestamp.keys(), reverse=True)
        selected_ts = timestamps[0]
        log(f"No timestamp specified. Selecting latest backup: {selected_ts}")

    return backups_by_timestamp[selected_ts], selected_ts

def restore_job(job_name, timestamp_prefix, config):
    jobs = config.get("jobs", [])
    job = next((j for j in jobs if j["name"] == job_name), None)
    
    if not job:
        log(f"Job '{job_name}' not found in configuration.")
        available_jobs = [j["name"] for j in jobs]
        log(f"Available jobs: {', '.join(available_jobs)}")
        return False

    defaults = config.get("defaults", {})
    nfs_config = config.get("nfs", {})
    mount_point = nfs_config.get("mountPoint", "/mnt/backups")
    
    container_name = job.get("containerName", job_name)
    backend = job.get("backend", defaults.get("backend", "docker"))
    volumes = job.get("volumes", [])
    service_name = job.get("serviceName")

    backup_dir = os.path.join(mount_point, "containers", job_name)
    
    if not os.path.isdir(backup_dir):
        log(f"Backup directory not found: {backup_dir}")
        return False

    # Find backup files
    backup_files_map, selected_ts = find_backups(backup_dir, timestamp_prefix)
    if not backup_files_map:
        log(f"Error: {selected_ts}") # selected_ts contains error msg here
        return False

    log(f"Restoring {job_name} from timestamp: {selected_ts}")

    # Confirmation
    print(f"\nWARNING: This will overwrite the following volumes for '{container_name}':")
    for vol in volumes:
        if vol in backup_files_map:
             print(f"  - {vol} <== {os.path.basename(backup_files_map[vol])}")
        else:
             print(f"  - {vol} (WARNING: No backup file found for this volume in this timestamp set)")
    
    confirm = input("\nAre you sure you want to continue? (yes/no): ")
    if confirm.lower() != "yes":
        log("Restore cancelled.")
        return False

    try:
        # Stop container/service
        if service_name:
            log(f"Stopping service {service_name}...")
            run_command(["systemctl", "stop", service_name], check=False)
        else:
            log(f"Stopping container {container_name}...")
            run_command([backend, "stop", container_name], check=False)

        # Restore volumes
        for vol in volumes:
            if vol not in backup_files_map:
                log(f"Skipping volume {vol}: No backup file found in set {selected_ts}")
                continue

            backup_file = backup_files_map[vol]
            log(f"Restoring volume {vol} from {backup_file}...")
            
            # Restore logic:
            # 1. Mount volume to /target
            # 2. Mount backup dir to /backup
            # 3. Wipe /target
            # 4. Untar backup to /target
            
            docker_cmd = [
                backend, "run", "--rm",
                "-v", f"{vol}:/target",
                "-v", f"{backup_dir}:/backup",
                "alpine:latest",
                "sh", "-c",
                f"rm -rf /target/* && tar xzf '/backup/{os.path.basename(backup_file)}' -C /target"
            ]
            
            if run_command(docker_cmd):
                log(f"Volume {vol} restored successfully.")
            else:
                log(f"Failed to restore volume {vol}")

    except Exception as e:
        log(f"Exception during restore: {e}")
        return False
    finally:
        # Restart container/service
        if service_name:
            log(f"Starting service {service_name}...")
            run_command(["systemctl", "start", service_name], check=False)
        else:
            log(f"Starting container {container_name}...")
            run_command([backend, "start", container_name], check=False)

    log(f"Restore completed for {job_name}.")
    return True

def main():
    parser = argparse.ArgumentParser(description="Restore container backups.")
    parser.add_argument("job_name", help="Name of the backup job (e.g., n8n, beszel)")
    parser.add_argument("--timestamp", "-t", help="Timestamp prefix (e.g., 20251201-191215). Defaults to latest.")
    parser.add_argument("--config", "-c", default=CONFIG_FILE, help=f"Path to configuration file (default: {CONFIG_FILE})")
    args = parser.parse_args()

    if not os.path.exists(args.config):
        log(f"Config file not found at {args.config}")
        sys.exit(1)

    with open(args.config, 'r') as f:
        config = json.load(f)

    nfs_config = config.get("nfs", {})
    if not ensure_mount(nfs_config):
        log("Aborting restore because NFS mount failed.")
        sys.exit(1)

    if os.geteuid() != 0:
        log("This script must be run as root.")
        sys.exit(1)

    restore_job(args.job_name, args.timestamp, config)

if __name__ == "__main__":
    main()
