# AGENTS.md

This document provides guidance for AI agents operating in this personal infrastructure repository.

## Repository Overview

This is a collection of infrastructure and configuration files for a homelab environment including:
- NixOS configurations for 4 cluster nodes (k1-k4)
- K3s HA Kubernetes cluster with distributed applications
- Docker compose services
- Reverse proxy configuration

## Repository Structure

```
/
├── k2/, k3/, k4/          # NixOS configs for cluster nodes (homelab)
├── k8s/                   # Kubernetes manifests for K3s cluster
├── caddy/                 # Caddy reverse proxy configuration
├── modules/               # Reusable NixOS modules
├── common/                # Shared NixOS configuration
├── docker/                # Docker compose files (deprecated, migrating to k8s)
└── k2/docker/, k3/docker/, k4/docker/  # Per-machine docker services
```

## Machine Registry

| Hostname | IP Address | OS | Purpose | Notes |
|----------|------------|-----|---------|-------|
| nas | 192.168.20.31 | TrueNAS | Network storage | Ugreen 4-bay NAS, provides NFS shares |
| k1 | 192.168.20.61 | NixOS | Media server | qBittorrent, Sonarr, Radarr, Prowlarr, Jellyfin, Jellyseerr |
| k2 | 192.168.20.62 | NixOS | K3s HA cluster (init) | Services: Karakeep, Memos, Papra, Ntfy, Linkding |
| k3 | 192.168.20.63 | NixOS | K3s HA cluster | Services: Audiobookshelf, n8n, OpenWebUI, SearXNG |
| k4 | 192.168.20.64 | NixOS | K3s HA cluster | Services: Beszel, Immich, various utilities |
| bee | 192.158.20.105 | Custom Bluefin Setup | Personal desktop | Beelink SER7 - daily driver. Config at `/var/home/crussell/Code/crussell-fin` |
| think | - | Custom Bluefin Setup | Laptop | ThinkPad T14 - portable development. Config at `/var/home/crussell/Code/crussell-fin` |
| Cluster VIP | 192.168.20.32 | Virtual | K3s HA endpoint | kube-vip managed IP |

## Build/Test Commands

This repository uses NixOS and has no traditional unit tests. Key commands:

```bash
# Check Nix config syntax for a machine
nix flake check .#nixosConfigurations.k2

# Build configuration (dry run)
nixos-rebuild build --flake .#k2

# Apply configuration to local machine
nixos-rebuild switch --flake .#k2

# Apply to remote machine (use nixos-anywhere for fresh installs)
nixos-rebuild switch --flake .#k2 --target-host root@192.168.20.62

# Update flake inputs
nix flake update

# Verify cluster health
kubectl get nodes
kubectl get pods -A
```

## NixOS Configuration

### Code Style

**Nix modules follow these patterns:**
- Use `{ config, pkgs, lib, ... }: let ... in ...` function form
- Define options with `mkOption` before `config`
- Use `mkEnableOption` for boolean flags
- Import modules at the top of configuration files
- Group related settings (networking, services, users) logically

**Example module structure:**
```nix
{ config, pkgs, lib, ... }:

let cfg = config.services.myService;
in {
  options.services.myService = {
    enable = lib.mkEnableOption "My Service";
    port = lib.mkOption { type = lib.types.port; default = 8080; };
  };

  config = lib.mkIf cfg.enable {
    # Configuration here
  };
};
```

### Key Modules

- `common/k3s-ha/` - K3s HA cluster configuration with kube-vip
- `modules/k3s.nix` - Single-node k3s for local development
- `modules/container-backup.nix` - Backup automation
- `modules/nixvim/` - Neovim configuration

## Kubernetes (k8s/)

### Deployment Pattern

1. Create namespace and resources in a subdirectory (e.g., `k8s/linkding/`)
2. Use `NodePort` services for external access
3. Longhorn storage class: `storageClassName: longhorn`
4. Apply with `kubectl apply -f k8s/<app>/`

**NodePort allocations (from k8s/README.md):**
- 30080: linkding
- 30081: immich (photos.crussell.io)
- 30082: open-webui
- 30083: papra
- 30084: searxng
- 30085: ntfy
- 30086: grafana

### Docker Swarm

**Dozzle stack (docker/swarm/dozzle-stack.yml):**
- Dozzle: Global deployment across k2, k3, k4
- AdGuardHome: Replicated deployment (1 instance) on k2 only (for consistent config storage)
- Deploy/Update: `cd docker/swarm && docker stack deploy -c dozzle-stack.yml dozzle`
- Check status: `docker service ls | grep dozzle`

**Important:** AdGuardHome must run as a single instance (not global) because each node has its own independent volume for configuration storage. If deployed globally, the load balancer would route to different nodes, each showing the installer.

**Port allocations (dozzle stack):**
- 8080: Dozzle Web UI
- 30053: AdGuardHome DNS (TCP/UDP)
- 30054: AdGuardHome HTTPS/DoH (after initial setup - configure via Web UI first)
- 30067-30068: AdGuardHome DHCP (UDP)
- 30100: AdGuardHome HTTP
- 30101: AdGuardHome DNS-over-TLS
- 30102: AdGuardHome Web UI (Caddy endpoint: adguard.internal.crussell.io)

**Important:** AdGuardHome requires initial setup via Web UI (port 30102) before HTTPS/DoH (port 30054) becomes functional. After setup, you can enable and configure the HTTPS server port.

**Caddy routing note (AdGuardHome):** after AdGuardHome setup completes, the UI often moves from :30102 (installer, container :3000) to :30100 (container :80). To avoid manual flip-flopping, set Caddy upstreams to both ports with first-available behavior.

**Volumes (local driver):**
- adguardhome-work: /opt/adguardhome/work
- adguardhome-conf: /opt/adguardhome/conf

**Network:** dozzle (overlay driver)

**Common issues:**
- Bind mounts: Ensure directories exist and are owned by the correct UID/GID for the container user
- Check permissions: `ls -la /path/to/data` - container user may not be root
- Fix ownership: `sudo chown -R <uid>:<gid> /path/to/data`
- Example: Audiobookshelf uses UID 999, so bind mounts need to be owned by 999:999

### K8s Resources

**Standard resources include:**
- Namespace (separated per app)
- PersistentVolumeClaim (using Longhorn)
- Deployment (with resource limits)
- Service (NodePort type)

**Resource limits guideline:**
- Small services: 100m CPU / 256Mi RAM request, 500m CPU / 512Mi RAM limit
- Medium services: 500m CPU / 512Mi RAM request, 2 CPU / 2Gi RAM limit

## Docker Compose

Docker compose files are located in per-machine directories:
- `k2/docker/` - Services specific to k2
- `k3/docker/` - Services specific to k3
- `k4/docker/` - Services specific to k4

**Usage:**
```bash
cd k2/docker/<service>
docker compose up -d
docker compose logs -f
```

Most services are being migrated to Kubernetes.

## Caddy Reverse Proxy

Caddy routes external traffic to internal services.

**Configuration files:**
- `caddy/Caddyfile` - Main reverse proxy config

**Routes services via:**
- Internal wildcard: `*.internal.crussell.io`
- Public domain: `*.crussell.io`

**Caddy runs in Docker container:**
- Container name: `caddy-proxy` (runs on k2)
- Config mounted from: `/home/crussell/caddy/Caddyfile` (not `/home/crussell/cn/caddy/Caddyfile`)
- Update script: `caddy/update_caddy.sh`

**Updating Caddy:**
```bash
# Run the update script (copies Caddyfile to k2 and restarts container)
./caddy/update_caddy.sh

# Or manually:
cat caddy/Caddyfile | ssh -i ~/.ssh/id_ed25519 k2 "cat > /home/crussell/caddy/Caddyfile"
ssh -i ~/.ssh/id_ed25519 k2 "docker restart caddy-proxy"
```

When adding a new service:
1. Add NodePort in k8s manifest
2. Add route block in Caddyfile
3. Run `./caddy/update_caddy.sh` to deploy changes

## Secrets Management

- Never commit secrets to git
- Use environment files (`.env`) for Docker compose
- Use Kubernetes secrets for k8s deployments
- Git-crypt is enabled for encrypted secrets in repository
- `.gitignore` blocks: `env.*`, `*.env`, `**/secrets.yaml`

## Python Scripts

Located in `docker/` directory:
- `backup.py` - Automated backup script
- `restore.py` - Backup restoration

**Python style:**
- Use f-strings for string formatting
- Use `subprocess.run()` for command execution
- Log with timestamps: `datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')`

## SSH Automation

For automated SSH operations:
- Use `ssh -i ~/.ssh/id_ed25519` to specify key explicitly when piping data
- Start SSH agent: `eval "$(ssh-agent -s)" && ssh-add ~/.ssh/id_ed25519`
- Deploy to k2: `cat file.yml | ssh -i ~/.ssh/id_ed25519 k2 "cat > /path/to/file.yml"`
- Caddy restart: `ssh -i ~/.ssh/id_ed25519 k2 "docker restart caddy-proxy"`
- Dozzle stack update: `ssh -i ~/.ssh/id_ed25519 k2 "cd /home/crussell/cn/docker/swarm && docker stack deploy -c dozzle-stack.yml dozzle"`

**Note:** Caddyfile is mounted at `/home/crussell/caddy/Caddyfile` (not `/home/crussell/cn/caddy/Caddyfile`) on k2.

## Where to Find Answers

**Cluster issues:**
- K8s manifests and deployment info: `k8s/README.md`
- Cluster node configurations: `k2/`, `k3/`, `k4/`
- Common cluster config: `common/k3s-ha/`

**Service routing:**
- Service to port mappings: `k8s/README.md` table
- Caddy routes: `caddy/Caddyfile`

**Machine-specific config:**
- Network config: Each machine's `configuration.nix` has systemd.network settings
- Storage: `disk-config.nix` in each machine directory

**Module reuse:**
  - Reusable components: `modules/`
  - Shared cluster settings: `common/`

## Restic Backups

Restic provides deduplicated, encrypted backups with flexible retention policies.

**Repository:** `/mnt/backups/restic` (shared across all nodes via NFS)
**Schedule:** Daily at 3:00 AM (systemd timer)
**Retention:** 90 days (24 hourly, 7 daily, 4 weekly, 3 monthly, 1 yearly)
**Backup type:** Entire volume backup for all services (no database dumps needed)

**Password Storage:**
- Location: `/etc/restic-password` on k2, k3, k4
- Synced manually (TODO: migrate to sops-nix/agenix)
- Stored in Bitwarden: Search for "Restic Backup Password - cn"
- Password: `YEYSW/uT9VxjHfYK4Y4KWqq6be7pztaTDA1jbi8gbPw=` (SAVE THIS NOW!)

**Service Distribution:**
- **k2:** Linkding, Karakeep, Memos, Papra, Ntfy, AdGuardHome, Caddy, Immich-Postgres, SearXNG
- **k3:** Audiobookshelf, Papra, n8n
- **k4:** Immich services (server, microservices, machine-learning)

**Running Backups:**
```bash
# Manual backup (k2)
ssh -i ~/.ssh/id_ed25519 k2 "sudo /opt/restic-backup.sh"

# Manual backup (k3)
ssh -i ~/.ssh/id_ed25519 k3 "sudo /opt/restic-backup.sh"

# Manual backup (k4)
ssh -i ~/.ssh/id_ed25519 k4 "sudo /opt/restic-backup.sh"

# Check backup logs
journalctl -u restic-backup -f
```

**Restoring:**
```bash
# List snapshots for service
ssh -i ~/.ssh/id_ed25519 k2 "restic snapshots --tag linkding --password-file /etc/restic-password --repo /mnt/backups/restic"

# Interactive restore (on k2)
ssh -i ~/.ssh/id_ed25519 k2 "sudo /opt/restic-restore.sh linkding"

# Specific snapshot restore (on k2)
ssh -i ~/.ssh/id_ed25519 k2 "sudo /opt/restic-restore.sh linkding abc123"
```

**Backup Configuration:**
- **k2:** `/etc/restic-backup.json` (Linkding, Karakeep, Memos, Papra, Ntfy, AdGuardHome, Caddy, Immich-Postgres, SearXNG)
- **k3:** `/etc/restic-backup.json` (Audiobookshelf, Papra, n8n)
- **k4:** `/etc/restic-backup.json` (Immich services with media exclusions)

**Storage Types:**
- **Volume backups:** Named Docker volumes (e.g., `karakeep-data`, `memos-data`)
- **Bind backups:** Host directories (e.g., `/mnt/swarm-data/linkding`, `/home/crussell/caddy/Caddyfile`)

**Adding New Services:**
1. Determine backup type: Check service volume with `docker inspect <container>`
   - `volume` (named Docker volume): Look for `Type: volume` in mounts
   - `bind` (host directory): Look for `Type: bind` in mounts
2. Find volume name or bind mount path:
   - Volume: Copy `Name` from volume mount (e.g., `karakeep-data`)
   - Bind: Copy `Source` from bind mount (e.g., `/mnt/swarm-data/linkding`)
3. Add to `/etc/restic-backup.json` on appropriate node:
   ```json
   {
     "name": "service-name",
     "type": "volume",
     "targets": ["volume-name"]
   }
   ```
   Or for bind mounts:
   ```json
   {
     "name": "service-name",
     "type": "bind",
     "targets": ["/path/on/host"],
     "pre_stop": "container-name",
     "post_start": "container-name"
   }
   ```
4. Test backup: `sudo /opt/restic-backup.sh`
5. Verify backup: `restic snapshots --tag service-name`
6. Update AGENTS.md with service details

**Common Issues:**
- **NFS mount failure:** Check NFS server availability, mount manually: `mount /mnt/backups`
- **Container not found:** Update `pre_stop`/`post_start` with correct container name (use partial match)
- **Repository corruption:** Run `restic check --read-data` and `restic repair` if needed
- **Disk space:** Run aggressive prune: `restic forget --prune`

**Monitoring:**
- Systemd journal: `journalctl -u restic-backup -f`
- Backup stats: `restic stats`
- Repo health: `restic check`

## Adding New Services

1. **For Kubernetes deployment:**
   - Create directory in `k8s/<service>/`
   - Add `manifest.yaml` with Namespace, PVC, Deployment, Service
   - Use Longhorn storage class
   - Allocate unused NodePort (check k8s/README.md)
   - Apply: `kubectl apply -f k8s/<service>/`

2. **For external access:**
   - Add route to `caddy/Caddyfile`
   - Add DNS A record to Route53 (managed manually)

 3. **For Docker deployment:**
    - Create directory in `kX/docker/<service>/`
    - Add `docker-compose.yml`
    - Create `.env` file (git-ignored) for secrets

 4. **For Docker Swarm deployment:**
    - Use `docker stack deploy -c <file> <stack-name>`
    - Check bind mount permissions: ensure directories exist and are owned by correct UID/GID
    - Fix permissions: `sudo chown -R <uid>:<gid> /path/to/data`
    - Troubleshoot: `docker service ps <service>` to see task status and errors

## Restic Backups

Restic provides deduplicated, encrypted backups with flexible retention policies.

**Repository:** `/mnt/backups/restic` (shared across all nodes via NFS)
**Schedule:** Daily at 3:00 AM (systemd timer)
**Retention:** 90 days (24 hourly, 7 daily, 4 weekly, 3 monthly, 1 yearly)
**Backup type:** Entire volume backup for all services (no database dumps needed)

**Password Storage:**
- Location: `/etc/restic-password` on k2, k3, k4
- Synced manually (TODO: migrate to sops-nix/agenix)
- Stored in Bitwarden: Search for "Restic Backup Password - cn"
- Password: `YEYSW/uT9VxjHfYK4Y4KWqq6be7pztaTDA1jbi8gbPw=` (SAVE THIS NOW!)

**Service Distribution:**
- **k2:** Linkding, Karakeep, Memos, Papra, Ntfy, AdGuardHome, Caddy, Immich-Postgres
- **k3:** Audiobookshelf, n8n, OpenWebUI, SearXNG
- **k4:** Beszel, Immich-App services

**Running Backups:**
```bash
# Manual backup (k2)
ssh -i ~/.ssh/id_ed25519 k2 "sudo /opt/restic-backup.sh"

# Manual backup (k3)
ssh -i ~/.ssh/id_ed25519 k3 "sudo /opt/restic-backup.sh"

# Manual backup (k4)
ssh -i ~/.ssh/id_ed25519 k4 "sudo /opt/restic-backup.sh"

# Check backup logs
journalctl -u restic-backup -f
```

**Restoring:**
```bash
# List snapshots for service
ssh -i ~/.ssh/id_ed25519 k2 "restic snapshots --tag linkding --password-file /etc/restic-password --repo /mnt/backups/restic"

# Interactive restore (on k2)
ssh -i ~/.ssh/id_ed25519 k2 "sudo /opt/restic-restore.sh linkding"

# Specific snapshot restore (on k2)
ssh -i ~/.ssh/id_ed25519 k2 "sudo /opt/restic-restore.sh linkding abc123"
```

**Backup Configuration:**
- **k2:** `/etc/restic-backup.json` (Linkding, Karakeep, Memos, Papra, Ntfy, AdGuardHome, Caddy, Immich-Postgres)
- **k3:** `/etc/restic-backup.json` (Audiobookshelf, n8n, OpenWebUI, SearXNG)
- **k4:** `/etc/restic-backup.json` (Beszel, Immich-App services)

**Storage Types:**
- **Volume backups:** Named Docker volumes (e.g., `karakeep-data`, `memos-data`)
- **Bind backups:** Host directories (e.g., `/mnt/swarm-data/linkding`, `/home/crussell/caddy/Caddyfile`)

**Adding New Services:**
1. Determine backup type: Check service volume with `docker inspect <container>`
   - `volume` (named Docker volume): Look for `Type: volume` in mounts
   - `bind` (host directory): Look for `Type: bind` in mounts
2. Find volume name or bind mount path:
   - Volume: Copy `Name` from volume mount (e.g., `karakeep-data`)
   - Bind: Copy `Source` from bind mount (e.g., `/mnt/swarm-data/linkding`)
3. Add to `/etc/restic-backup.json` on appropriate node:
   ```json
   {
     "name": "service-name",
     "type": "volume",
     "targets": ["volume-name"]
   }
   ```
   Or for bind mounts:
   ```json
   {
     "name": "service-name",
     "type": "bind",
     "targets": ["/path/on/host"],
     "pre_stop": "container-name",
     "post_start": "container-name"
   }
   ```
4. Test backup: `sudo /opt/restic-backup.sh`
5. Verify backup: `restic snapshots --tag service-name`
6. Update AGENTS.md with service details

**Common Issues:**
- **NFS mount failure:** Check NFS server availability, mount manually: `mount /mnt/backups`
- **Container not found:** Update `pre_stop`/`post_start` with correct container name (use partial match)
- **Repository corruption:** Run `restic check --read-data` and `restic repair` if needed
- **Disk space:** Run aggressive prune: `restic forget --prune`

**Monitoring:**
- Systemd journal: `journalctl -u restic-backup -f`
- Backup stats: `restic stats`
- Repo health: `restic check`

## NIC Drop Monitoring

`ethtool-drop-monitor` logs RX drop/miss deltas every minute via a systemd timer; view with `journalctl -u ethtool-drop-monitor -f`. Some NICs may not expose `rx_no_buffer_count`, which is safe to ignore.
