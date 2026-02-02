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

**Volumes (local driver):**
- adguardhome-work: /opt/adguardhome/work
- adguardhome-conf: /opt/adguardhome/conf

**Network:** dozzle (overlay driver)

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

## NIC Drop Monitoring

`ethtool-drop-monitor` logs RX drop/miss deltas every minute via a systemd timer; view with `journalctl -u ethtool-drop-monitor -f`. Some NICs may not expose `rx_no_buffer_count`, which is safe to ignore.
