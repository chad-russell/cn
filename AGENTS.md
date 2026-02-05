# AGENTS.md

This document provides guidance for AI agents operating in this personal infrastructure repository.

## Repository Overview

This is a collection of infrastructure and configuration files for a homelab environment including:
- NixOS configurations for 4 cluster nodes (k1-k4)
- Docker Swarm with distributed applications (migrated from K3s Kubernetes in Feb 2026)
- Docker compose services for standalone deployments
- Reverse proxy configuration

## Repository Structure

```
/
├── k2/, k3/, k4/          # NixOS configs for cluster nodes (homelab)
├── k8s/                   # DEPRECATED - Kubernetes manifests (migrated to Docker Swarm Feb 2026)
├── caddy/                 # Caddy reverse proxy configuration
├── modules/               # Reusable NixOS modules
├── common/                # Shared NixOS configuration
├── docker/                # Docker Swarm stack configurations
│   └── swarm/             # Docker Swarm stacks (active deployments)
└── k2/docker/, k3/docker/, k4/docker/  # Per-machine standalone docker compose services
```

## Machine Registry

| Hostname | IP Address | OS | Purpose | Notes |
|----------|------------|-----|---------|-------|
| nas | 192.168.20.31 | TrueNAS | Network storage | Ugreen 4-bay NAS, provides NFS shares |
| k1 | 192.168.20.61 | NixOS | Media server | qBittorrent, Sonarr, Radarr, Prowlarr, Jellyfin, Jellyseerr |
| k2 | 192.168.20.62 | NixOS | Docker Swarm manager | Karakeep, Memos, Papra, Ntfy, Linkding, Audiobookshelf, AdGuardHome, Caddy |
| k3 | 192.168.20.63 | NixOS | Docker Swarm worker | n8n, OpenWebUI, SearXNG |
| k4 | 192.168.20.64 | NixOS | Docker Swarm worker | Beszel, Immich services |
| bee | 192.158.20.105 | Custom Bluefin Setup | Personal desktop | Beelink SER7 - daily driver. Config at `/var/home/crussell/Code/crussell-fin` |
| think | - | Custom Bluefin Setup | Laptop | ThinkPad T14 - portable development. Config at `/var/home/crussell/Code/crussell-fin` |

## Remote Deployment Workflow

When making changes to NixOS configs or Docker Swarm stacks for k2/k3/k4, follow this workflow:

### General Pattern

1. Make changes locally (edit files in `k2/`, `k3/`, `k4/`, or `docker/swarm/`)
2. Commit and push changes: `git add . && git commit -m "description" && git push`
3. Pull changes on remote nodes using the helper script
4. Apply changes (nixos-rebuild switch, docker stack deploy, etc.)

### Helper Scripts

The `scripts/` directory contains helper scripts for remote deployment:

```bash
# Pull latest changes on all nodes (or specific nodes)
./scripts/pull-nodes.sh          # Pull on k2, k3, k4
./scripts/pull-nodes.sh k2 k4    # Pull only on k2 and k4

# Deploy Docker Swarm stack (runs on k2, manages cluster)
./scripts/deploy-stack.sh dozzle-stack.yml
./scripts/deploy-stack.sh beszel-stack.yml beszel

# Apply NixOS config to remote nodes
./scripts/apply-nixos.sh k2
./scripts/apply-nixos.sh k2 k3 k4
```

All scripts use SSH key `~/.ssh/id_ed25519` and connect as `crussell` user. They automatically handle proper SSH options to avoid authentication issues.

### Common Deployment Tasks

**Docker Swarm Stacks:**
- Stack files are located in `docker/swarm/`
- Deployed from k2 (Swarm manager)
- All nodes must have latest code before deploying
- Example: `./scripts/pull-nodes.sh && ssh -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes crussell@192.168.20.62 "cd /home/crussell/cn/docker/swarm && docker stack deploy -c dozzle-stack.yml dozzle"`

**NixOS Configuration Changes:**
- Node-specific configs: `k2/`, `k3/`, `k4/`
- Common modules: `common/`, `modules/`
- Must pull on target node before applying
- Example: `./scripts/pull-nodes.sh && ssh -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes crussell@192.168.20.62 "cd /home/crussell/cn && sudo nixos-rebuild switch --flake .#k2"`

**Caddy Reverse Proxy:**
- Config: `caddy/Caddyfile`
- Update script: `./caddy/update_caddy.sh`
- Script copies Caddyfile to k2 and restarts container

### SSH Configuration

- SSH key: `~/.ssh/id_ed25519`
- Username: `crussell` (use `-o IdentitiesOnly=yes` to avoid agent issues)
- Root access for some operations (prefix with `sudo`)
- IP addresses: k2=192.168.20.62, k3=192.168.20.63, k4=192.168.20.64

### Troubleshooting

**SSH "Too many authentication failures":**
Use `-o IdentitiesOnly=yes` with the ssh command to specify the exact key.

**Merge conflicts on pull:**
Remove untracked files first: `rm <untracked-file>` then pull again.

**Docker Swarm service not starting:**
Check logs: `docker service logs <service-name>`
Check task status: `docker service ps <service-name>`

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

# Docker Swarm management (on k2)
docker stack ls                                    # List all stacks
docker stack services <stack-name>                 # List services in a stack
docker service ps <service-name>                   # Check service status and task history
docker stack logs <stack-name>                     # View stack logs
docker stack deploy -c <compose-file.yml> <stack> # Deploy/update a stack
docker stack rm <stack-name>                      # Remove a stack

# SSH into k2 for Docker Swarm management
ssh -i ~/.ssh/id_ed25519 k2 "cd /home/crussell/cn/docker/swarm && docker stack deploy -c audiobookshelf-swarm.yml audiobookshelf"

# Monitor Docker Swarm services
docker service ls                                 # List all services across all stacks
docker ps                                          # List running containers
docker logs -f <container-name>                   # Follow container logs
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

> ⚠️ **Note:** k3s modules are no longer actively used (migrated to Docker Swarm in Feb 2026). Preserved for reference or potential rollback.

- `common/k3s-ha/` - **DEPRECATED** - K3s HA cluster configuration with kube-vip
- `modules/k3s.nix` - **DEPRECATED** - Single-node k3s for local development
- `modules/restic-backup.nix` - Restic backup automation
- `modules/nixvim/` - Neovim configuration

## Kubernetes (k8s/)

> ⚠️ **DEPRECATED**: The Kubernetes deployment method has been **migrated to Docker Swarm** as of February 2026. The k8s/ directory contains legacy configurations that are no longer maintained or used. All services previously running on K3s Kubernetes are now deployed via Docker Swarm stacks in `docker/swarm/`.

### Legacy Deployment Pattern (Archived)

> These instructions are preserved for historical reference only. All deployments are now managed via Docker Swarm.

1. Create namespace and resources in a subdirectory (e.g., `k8s/linkding/`)
2. Use `NodePort` services for external access
3. Longhorn storage class: `storageClassName: longhorn`
4. Apply with `kubectl apply -f k8s/<app>/`

**Legacy NodePort allocations (archived):**
- 30080: linkding
- 30081: immich (photos.crussell.io)
- 30082: open-webui
- 30083: papra
- 30084: searxng
- 30085: ntfy
- 30086: grafana
- 30337: audiobookshelf (now on Docker Swarm, same port)

### Docker Swarm

Docker Swarm is the primary deployment method for all services (migrated from K3s Kubernetes in Feb 2026). Stacks are defined in `docker/swarm/` directory.

#### Deployment Commands

```bash
# Deploy/update a stack
cd /home/crussell/Code/cn/docker/swarm
docker stack deploy -c <stack-file.yml> <stack-name>

# List all stacks and services
docker stack ls
docker stack services <stack-name>

# Check service status and task history
docker service ps <service-name>

# View stack logs
docker stack logs <stack-name>

# Remove a stack
docker stack rm <stack-name>
```

**Note:** k2, k3, k4 are NixOS machines; use SSH to execute commands remotely:
```bash
ssh -i ~/.ssh/id_ed25519 k2 "cd /home/crussell/cn/docker/swarm && docker stack deploy -c audiobookshelf-swarm.yml audiobookshelf"
```

#### Audiobookshelf Stack (docker/swarm/audiobookshelf-swarm.yml)

**Status:** ✅ Active (migrated from k8s in Feb 2026)
- **Image:** `ghcr.io/advplyr/audiobookshelf:latest`
- **Placement:** k2 node only (replica: 1)
- **Port:** 30337 (NodePort)
- **Environment:**
  - `TZ=America/New_York`
  - `AUDIOBOOKSHELF_HOSTNAME=audiobookshelf`
- **Volumes:** `/mnt/swarm-data/audiobookshelf/` (audiobooks, config, metadata, podcasts)
- **Restart policy:** on-failure, max 3 attempts
- **Deploy:** `docker stack deploy -c audiobookshelf-swarm.yml audiobookshelf`
- **Check:** `docker service ls | grep audiobookshelf`
- **UID:** Container runs as UID 999 (ensure bind mounts are owned by 999:999)

#### Dozzle Stack (docker/swarm/dozzle-stack.yml)

- Dozzle: Global deployment across k2, k3, k4
- AdGuardHome: Replicated deployment (1 instance) on k2 only (for consistent config storage)
- Deploy/Update: `docker stack deploy -c dozzle-stack.yml dozzle`
- Check status: `docker service ls | grep dozzle`

Note: k2, k3, k4 are NixOS machines; use SSH to execute commands remotely.

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

**Resource limits guideline (archived):**
> This section is preserved for historical reference only. Resource limits for Docker Swarm follow similar patterns but are specified differently in stack files.

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

**Note:** Docker compose is used for standalone services not managed by Docker Swarm stacks. Most services are deployed via Docker Swarm stacks in `docker/swarm/`.

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
1. Prefer adding to docker swarm
2. Add route block in Caddyfile
3. Run `./caddy/update_caddy.sh` to deploy changes

## Secrets Management

- NEVER commit secrets to git
- Use environment files (`.env`) for Docker compose

## Python Scripts

(Deprecated) legacy backup scripts previously lived under `docker/`; backups are now handled by `modules/restic-backup.nix`.

## SSH Automation

For automated SSH operations:
- Use `ssh -i ~/.ssh/id_ed25519` to specify key explicitly when piping data
- Start SSH agent: `eval "$(ssh-agent -s)" && ssh-add ~/.ssh/id_ed25519`
- Deploy to k2: `cat file.yml | ssh -i ~/.ssh/id_ed25519 k2 "cat > /path/to/file.yml"`
- Caddy restart: `ssh -i ~/.ssh/id_ed25519 k2 "docker restart caddy-proxy"`
- Dozzle stack update: `ssh -i ~/.ssh/id_ed25519 k2 "cd /home/crussell/cn/docker/swarm && docker stack deploy -c dozzle-stack.yml dozzle"`

**Note:** Caddyfile is mounted at `/home/crussell/caddy/Caddyfile` (not `/home/crussell/cn/caddy/Caddyfile`) on k2.

## Where to Find Answers

> ⚠️ **Note:** k8s configurations are deprecated (migrated to Docker Swarm Feb 2026). Legacy info preserved for reference.

**Cluster issues (archived):**
- K8s manifests and deployment info: `k8s/README.md` (legacy)
- Cluster node configurations: `k2/`, `k3/`, `k4/`
- Common cluster config: `common/k3s-ha/` (deprecated)

**Current Service Management:**
- Docker Swarm stacks: `docker/swarm/`
- Stack deployment guide: See "## Docker Swarm" section above
- Service monitoring: Docker Swarm commands and Peekaping

**Service routing:**
- Service to port mappings: See Docker Swarm stack files in `docker/swarm/`
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

**Service Distribution:**
- **k2:** Audiobookshelf, Linkding, Karakeep, Memos, Papra, Ntfy, AdGuardHome, Caddy, Immich-Postgres, SearXNG
- **k3:** n8n, OpenWebUI
- **k4:** Immich services (server, microservices, machine-learning)

**Running Backups:**
```bash
# Manual backup (k2)
ssh -i ~/.ssh/id_ed25519 k2 "sudo restic-backup"

# Manual backup (k3)
ssh -i ~/.ssh/id_ed25519 k3 "sudo restic-backup"

# Manual backup (k4)
ssh -i ~/.ssh/id_ed25519 k4 "sudo restic-backup"

# Check backup logs
journalctl -u restic-backup -f
```

**Verifying Backups:**
```bash
ssh -i ~/.ssh/id_ed25519 k2 "sudo restic snapshots --repo /mnt/backups/restic --password-file /etc/restic-password"
ssh -i ~/.ssh/id_ed25519 k2 "sudo restic snapshots --repo /mnt/backups/restic --password-file /etc/restic-password --tag karakeep"
```

**Backup Configuration:**
- NixOS option: `services.resticBackup.configFile`
- Source files (in flake): `backups/restic/k2.json`, `backups/restic/k3.json`, `backups/restic/k4.json`

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
4. Test backup
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

 1. **For external access:**
   - Add route to `caddy/Caddyfile`
   - Add DNS A record to Route53 (managed manually)

 2. **For Docker Swarm deployment:**
    - Use `docker stack deploy -c <file> <stack-name>`
    - Check bind mount permissions: ensure directories exist and are owned by correct UID/GID
    - Fix permissions: `sudo chown -R <uid>:<gid> /path/to/data`
    - Troubleshoot: `docker service ps <service>` to see task status and errors

## NIC Drop Monitoring

`ethtool-drop-monitor` logs RX drop/miss deltas every minute via a systemd timer; view with `journalctl -u ethtool-drop-monitor -f`. Some NICs may not expose `rx_no_buffer_count`, which is safe to ignore.

## Creating Desktop Web Apps

For creating desktop apps from websites (e.g., web apps, localhost services), use the Brunch configuration system in `~/Code/cn/brunch/`.

### Architecture

Brunch uses `makeWebAppExecutable(url)` which creates a wrapper that launches Chrome in app mode:
```
flatpak run com.google.Chrome --app=<url>
```

This creates a standalone desktop entry file (`.desktop`) that launches the website as a native-looking application.

### Adding a New Web App

1. **Find or create an icon:**
   - Download favicon or icon from the website
   - Copy to `brunch/config/static/<app-name>-icon.svg` (or `.png`)

2. **Add to brunch configuration (`brunch/config/brunch.bri`):**
   ```typescript
   import { makeBrunch, makeWebAppExecutable } from "brunch";

   // Import the icon
   const appIcon = Brioche.includeFile("./static/app-icon.svg");

   export default function() {
     return makeBrunch({
       desktopApps: [
         {
           name: "app-name",  // Used for desktop entry and symlink
           executable: makeWebAppExecutable("https://example.com"),
           icon: appIcon,
           iconExt: "svg",    // or "png"
           comment: "Short description",
           categories: ["Development"],  // See freedesktop.org categories
         },
       ],
     });
   }
   ```

3. **Rebuild and apply brunch:**
   ```bash
   cd ~/Code/cn/brunch/src && brioche install -p .
   cd ~/Code/cn/brunch && ~/.local/share/brioche/installed/bin/brunch apply ./config
   ```

### Example: Opencode App

Located in `brunch/config/brunch.bri`:
```typescript
const opencodeIcon = Brioche.includeFile("./static/opencode-logo-dark.svg");

{
  name: "opencode",
  executable: makeWebAppExecutable("http://localhost:4096"),
  icon: opencodeIcon,
  iconExt: "svg",
  comment: "Interactive CLI tool for software engineering",
  categories: ["Development"],
}
```

### Desktop Entry Details

Generated `.desktop` files follow XDG specification:
- Location: `~/.local/share/applications/<app-name>.desktop`
- Icon: `~/.local/share/icons/hicolor/scalable/apps/<app-name>.<ext>`
- Executable: `~/.local/bin/<app-name>` (symlink to brioche-run)

### Common Desktop Categories

- "Development" - Programming tools
- "Network" - Web browsers and network apps
- "Utility" - General-purpose apps
- "Graphics" - Image/graphics editors
- "Office" - Productivity apps
- "System" - System utilities

Full list: https://specifications.freedesktop.org/menu-spec/latest/apa.html

## Peekaping (Uptime Monitoring)

**Purpose:** Self-hosted uptime monitoring with REST API for Docker Swarm services

**Deployment:**
- Stack: `docker/swarm/peekaping-stack.yml`
- Port: 30087 (internal)
- URL: https://peekaping.internal.crussell.io
- Database: SQLite (volume: peekaping-data)

**Skills:**
- Management skill: `/var/home/linuxbrew/.linuxbrew/lib/node_modules/openclaw/skills/peekaping/SKILL.md`
- API setup script: `docker/swarm/add-peekaping-monitors-api.sh`
- Setup guide script: `docker/swarm/setup-peekaping-monitors.sh`
- Monitor JSON: `docker/swarm/peekaping-monitors.json`

**Services Monitored (22 total):**
- Internal domain (`*.internal.crussell.io`): 18 services
- Public domain (`*.crussell.io`): 4 services
- All services routed through Caddy reverse proxy

**API Credentials:**
- Key ID: `b3377891-0811-4da3-95d9-147f0c333ce9`
- Key Secret: `pryKw3pLoYFw9uC0vGu2mezoPDSTrmViD8ljCd9iNwg=`

**Usage:**
```bash
# Run API setup script
cd /home/crussell/Code/cn/docker/swarm
./add-peekaping-monitors-api.sh

# Check Peekaping status
curl -s https://peekaping.internal.crussell.io/api/v1/monitors \
  -H "X-API-Key-ID: b3377891-0811-4da3-95d9-147f0c333ce9" \
  -H "X-API-Key-Secret: pryKw3pLoYFw9uC0vGu2mezoPDSTrmViD8ljCd9iNwg="
```

**Alert Channels:**
- Telegram (recommended): Create bot via @BotFather, add chat ID from https://t.me/userinfobot
- NTFY (self-hosted): Server: https://ntfy.internal.crussell.io, Topic: peekaping-alerts or wavy-dave

**Docker Health Checks:**
Added to swarm stacks:
- Karakeep (main + meilisearch): HTTP health checks
- Immich (postgres, redis, server): pg_isready, redis-cli ping, HTTP ping
- SearXNG: HTTP /healthz endpoint
- Papra: HTTP root endpoint
- Ntfy: HTTP /v1 API endpoint
