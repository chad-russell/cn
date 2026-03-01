# Quadlet Migration Plan

Complete plan for migrating from Docker Swarm to Podman Quadlets on a single server.

## Overview

- **Source:** Docker Swarm across k2, k3, k4
- **Destination:** Single machine with Podman Quadlets (rootless)
- **New Server IP:** 192.168.20.105
- **Data path:** `/srv/` (local state), `/mnt/nas/` (NFS from NAS)

## Status (2026-02-24)

### ✅ Completed
- [x] Server image build (Containerfile, Justfile)
- [x] Quadlet configuration files created
- [x] Quadlet setup script created and run
- [x] `/srv/` directory structure created
- [x] Data migrated from k2 to `/srv/` (~5.5GB)
- [x] SELinux labels fixed on `/srv/`
- [x] Firewall ports opened on new server
- [x] All single-container services running and healthy
- [x] Caddy routes updated to 192.168.20.105
- [x] All services accessible via Caddy reverse proxy

### ⚠️ Pending
- [ ] Immich pod configuration (port conflict between server and microservices)
  - **Issue:** Both server and microservices try to bind port 2283
  - **Current status:** Podman kube pods don't handle multiple containers binding to same port well
  - **Options:** 
    1. Switch to individual container quadlets (most stable)
    2. Use nginx proxy inside pod
    3. Configure server to not listen (proxy-only mode)

## Services

### Single Containers (`.container` files)

| Service | Port | Data Path | Status |
|---------|------|-----------|--------|
| linkding | 30080 | `/srv/linkding/data` | ✅ Running, Healthy |
| papra | 30083 | `/srv/papra/data` | ✅ Running, Healthy |
| ntfy | 30085 | `/srv/ntfy/cache` | ✅ Running, Healthy |
| peekaping | 30087 | `/srv/peekaping/data` | ✅ Running, Healthy |
| audiobookshelf | 30337 | `/srv/audiobookshelf/{audiobooks,config,metadata,podcasts}` | ✅ Running, Healthy |
| adguardhome | 30053,30100,30054,30101,30102 | `/srv/adguardhome/{work,conf}` | ✅ Running |

### Pod-Based (`.kube` files)

| Service | Containers | Port | Data Path | Status |
|---------|------------|------|-----------|--------|
| searxng | searxng + valkey | 30084 | `/srv/searxng/{settings.yml,valkey/}` | ✅ Running, Healthy |
| karakeep | karakeep + chrome + meilisearch | 30092 | `/srv/karakeep/{data,meilisearch}` | ✅ Running, Healthy |
| immich | postgres + redis + server + microservices + ml | 30093 | `/srv/immich/postgres` + `/mnt/nas/photos` | ⚠️ Port conflict |

---

## Directory Structure

```
crussell-srv/
├── quadlets/
│   ├── setup-quadlets.sh
│   ├── migrate-data.sh
│   ├── containers/
│   │   ├── linkding.container
│   │   ├── papra.container
│   │   ├── ntfy.container
│   │   ├── peekaping.container
│   │   ├── audiobookshelf.container
│   │   └── adguardhome.container
│   ├── pods/
│   │   ├── searxng/
│   │   │   ├── searxng.kube
│   │   │   └── searxng.yml
│   │   ├── karakeep/
│   │   │   ├── karakeep.kube
│   │   │   └── karakeep.yml
│   │   └── immich/
│   │       ├── immich.kube
│   │       └── immich.yml
│   └── config/
│       ├── immich-postgresql.conf
│       └── searxng-settings.yml
└── MIGRATION.md (this file)
```

---

## Storage Layout

```
/srv/
├── linkding/
│   └── data/
├── papra/
│   └── data/
├── ntfy/
│   └── cache/
├── peekaping/
│   └── data/
├── audiobookshelf/
│   ├── audiobooks/
│   ├── config/
│   ├── metadata/
│   └── podcasts/
├── adguardhome/
│   ├── work/
│   └── conf/
├── searxng/
│   ├── settings.yml
│   └── valkey/
├── karakeep/
│   ├── data/
│   └── meilisearch/
└── immich/
    ├── postgres/
    └── postgresql.conf

/mnt/nas/
└── photos/          # NFS mount from 192.168.20.31:/mnt/tank/photos
```

---

## Quadlet Files

### Single Containers

#### linkding.container
```ini
[Unit]
Description=Linkding Bookmark Manager
After=network-online.target
Wants=network-online.target

[Container]
Image=docker.io/sissbruecker/linkding:latest
PublishPort=30080:9090
Volume=/srv/linkding/data:/etc/linkding/data
Environment=LD_CSRF_TRUSTED_ORIGINS=https://linkding.internal.crussell.io
Environment=LD_DISABLE_BACKGROUND_TASKS=False

[Service]
Restart=unless-stopped
RestartSec=5

[Install]
WantedBy=default.target
```

#### papra.container
```ini
[Unit]
Description=Papra Document Manager
After=network-online.target
Wants=network-online.target

[Container]
Image=ghcr.io/papra-hq/papra:latest
PublishPort=30083:1221
Volume=/srv/papra/data:/app/app-data
Environment=AUTH_SECRET=papra-auth-secret-change-me
Environment=APP_BASE_URL=https://papra.internal.crussell.io
Environment=TZ=America/New_York

[Service]
Restart=unless-stopped

[Install]
WantedBy=default.target
```

#### ntfy.container
```ini
[Unit]
Description=Ntfy Push Notifications
After=network-online.target
Wants=network-online.target

[Container]
Image=docker.io/binwiederhier/ntfy:v2.11.0
PublishPort=30085:80
Volume=/srv/ntfy/cache:/var/cache/ntfy
Environment=TZ=America/New_York
Environment=NTFY_BASE_URL=https://ntfy.internal.crussell.io
Exec=serve
HealthCmd=/usr/bin/wget --quiet --tries=1 --spider http://localhost:80/v1
HealthInterval=30s
HealthTimeout=10s
HealthRetries=3
HealthStartPeriod=40s

[Service]
Restart=on-failure

[Install]
WantedBy=default.target
```

#### peekaping.container
```ini
[Unit]
Description=Peekaping Uptime Monitor
After=network-online.target
Wants=network-online.target

[Container]
Image=docker.io/0xfurai/peekaping-bundle-sqlite:latest
PublishPort=30087:8383
Volume=/srv/peekaping/data:/app/data
Environment=DB_NAME=/app/data/peekaping.db
Environment=TZ=America/New_York
HealthCmd=/usr/bin/wget --quiet --tries=1 --spider http://localhost:8383/
HealthInterval=30s
HealthTimeout=10s
HealthRetries=3
HealthStartPeriod=40s

[Service]
Restart=on-failure

[Install]
WantedBy=default.target
```

#### audiobookshelf.container
```ini
[Unit]
Description=Audiobookshelf Audiobook/Podcast Server
After=network-online.target
Wants=network-online.target

[Container]
Image=ghcr.io/advplyr/audiobookshelf:latest
PublishPort=30337:80
Volume=/srv/audiobookshelf/audiobooks:/audiobooks
Volume=/srv/audiobookshelf/config:/config
Volume=/srv/audiobookshelf/metadata:/metadata
Volume=/srv/audiobookshelf/podcasts:/app/podcasts
Environment=TZ=America/New_York
Environment=AUDIOBOOKSHELF_HOSTNAME=audiobookshelf
HealthCmd=/usr/bin/wget --quiet --tries=1 --spider http://localhost:80/
HealthInterval=30s
HealthTimeout=10s
HealthRetries=3
HealthStartPeriod=60s

[Service]
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
```

#### adguardhome.container
```ini
[Unit]
Description=AdGuardHome DNS Server
After=network-online.target
Wants=network-online.target

[Container]
Image=docker.io/adguard/adguardhome:latest
PublishPort=30053:53/tcp
PublishPort=30053:53/udp
PublishPort=30100:80/tcp
PublishPort=30054:443/tcp
PublishPort=30101:853/tcp
PublishPort=30102:3000/tcp
Volume=/srv/adguardhome/work:/opt/adguardhome/work
Volume=/srv/adguardhome/conf:/opt/adguardhome/conf

[Service]
Restart=on-failure

[Install]
WantedBy=default.target
```

---

### Pods

#### searxng/

**searxng.kube**
```ini
[Unit]
Description=SearXNG Search Engine Pod
After=network-online.target
Wants=network-online.target

[Kube]
Yaml=searxng.yml
PublishPort=30084:8080

[Install]
WantedBy=default.target
```

**searxng.yml**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: searxng
spec:
  containers:
    - name: searxng
      image: docker.io/searxng/searxng:latest
      env:
        - name: SEARXNG_BASE_URL
          value: https://searxng.internal.crussell.io/
        - name: SEARXNG_REDIS_URL
          value: redis://localhost:6379/0
      volumeMounts:
        - name: settings
          mountPath: /etc/searxng/settings.yml
          subPath: settings.yml
          readOnly: true
      livenessProbe:
        httpGet:
          path: /healthz
          port: 8080
        initialDelaySeconds: 40
        periodSeconds: 30
        timeoutSeconds: 10
        failureThreshold: 3

    - name: valkey
      image: docker.io/valkey/valkey:8-alpine
      args:
        - valkey-server
        - --save
        - "30"
        - "1"
        - --loglevel
        - warning
      volumeMounts:
        - name: valkey-data
          mountPath: /data

  volumes:
    - name: settings
      hostPath:
        path: /srv/searxng/settings.yml
        type: File
    - name: valkey-data
      hostPath:
        path: /srv/searxng/valkey
        type: DirectoryOrCreate
```

#### karakeep/

**karakeep.kube**
```ini
[Unit]
Description=Karakeep Bookmarking Pod
After=network-online.target
Wants=network-online.target

[Kube]
Yaml=karakeep.yml
PublishPort=30092:3000

[Install]
WantedBy=default.target
```

**karakeep.yml**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: karakeep
spec:
  containers:
    - name: karakeep
      image: ghcr.io/karakeep-app/karakeep:release
      env:
        - name: DATA_DIR
          value: /data
        - name: MEILI_ADDR
          value: http://localhost:7700
        - name: BROWSER_WEB_URL
          value: http://localhost:9222
        - name: MEILI_MASTER_KEY
          value: "karakeep-master-key-change-me"
        - name: NEXTAUTH_SECRET
          value: "change-me-or-use-a-secret"
      volumeMounts:
        - name: data
          mountPath: /data

    - name: chrome
      image: gcr.io/zenika-hub/alpine-chrome:124
      args:
        - --no-sandbox
        - --disable-gpu
        - --disable-dev-shm-usage
        - --remote-debugging-address=0.0.0.0
        - --remote-debugging-port=9222
        - --hide-scrollbars
      securityContext:
        capabilities:
          add: ["SYS_ADMIN"]

    - name: meilisearch
      image: docker.io/getmeili/meilisearch:v1.10
      env:
        - name: MEILI_MASTER_KEY
          value: "karakeep-master-key-change-me"
        - name: MEILI_NO_ANALYTICS
          value: "true"
      volumeMounts:
        - name: meilisearch-data
          mountPath: /meili_data

  volumes:
    - name: data
      hostPath:
        path: /srv/karakeep/data
        type: DirectoryOrCreate
    - name: meilisearch-data
      hostPath:
        path: /srv/karakeep/meilisearch
        type: DirectoryOrCreate
```

#### immich/

**immich.kube**
```ini
[Unit]
Description=Immich Photo Management Pod
After=network-online.target
Wants=network-online.target

[Kube]
Yaml=immich.yml
PublishPort=30093:2283

[Install]
WantedBy=default.target
```

**immich.yml**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: immich
spec:
  initContainers:
    - name: init-permissions
      image: docker.io/busybox
      command: ['sh', '-c', 'mkdir -p /data && chmod 777 /data']
      volumeMounts:
        - name: postgres-data
          mountPath: /data

  containers:
    - name: postgres
      image: ghcr.io/tensorchord/cloudnative-vectorchord:16.9-0.4.3
      env:
        - name: POSTGRES_DB
          value: immich
        - name: POSTGRES_USER
          value: immich
        - name: POSTGRES_PASSWORD
          value: "immich_secret_password_change_me"
        - name: PGDATA
          value: /var/lib/postgresql/data
      command:
        - postgres
        - -c
        - config_file=/etc/postgresql/postgresql.conf
      volumeMounts:
        - name: postgres-data
          mountPath: /var/lib/postgresql/data
        - name: postgres-config
          mountPath: /etc/postgresql/postgresql.conf
          subPath: postgresql.conf
      livenessProbe:
        exec:
          command:
            - pg_isready
            - -U
            - immich
            - -d
            - immich
        initialDelaySeconds: 10
        periodSeconds: 10
        timeoutSeconds: 5
        failureThreshold: 5

    - name: redis
      image: docker.io/redis:7-alpine
      args:
        - redis-server
        - --save
        - "60"
        - "1"
        - --loglevel
        - warning
      livenessProbe:
        exec:
          command:
            - redis-cli
            - ping
        initialDelaySeconds: 10
        periodSeconds: 10
        timeoutSeconds: 3
        failureThreshold: 5

    - name: server
      image: ghcr.io/immich-app/immich-server:release
      args:
        - start.sh
        - immich
      env:
        - name: DB_HOSTNAME
          value: localhost
        - name: DB_USERNAME
          value: immich
        - name: DB_PASSWORD
          value: "immich_secret_password_change_me"
        - name: DB_DATABASE_NAME
          value: immich
        - name: REDIS_HOSTNAME
          value: localhost
        - name: TYPESENSE_ENABLED
          value: "false"
        - name: DISABLE_MACHINE_LEARNING
          value: "false"
        - name: MACHINE_LEARNING_HOST
          value: localhost
        - name: MACHINE_LEARNING_PORT
          value: "3003"
      volumeMounts:
        - name: photos
          mountPath: /usr/src/app/upload
      livenessProbe:
        httpGet:
          path: /api/server-info/ping
          port: 2283
        initialDelaySeconds: 60
        periodSeconds: 30
        timeoutSeconds: 10
        failureThreshold: 3

    - name: microservices
      image: ghcr.io/immich-app/immich-server:release
      args:
        - start.sh
        - microservices
      env:
        - name: DB_HOSTNAME
          value: localhost
        - name: DB_USERNAME
          value: immich
        - name: DB_PASSWORD
          value: "immich_secret_password_change_me"
        - name: DB_DATABASE_NAME
          value: immich
        - name: REDIS_HOSTNAME
          value: localhost
        - name: TYPESENSE_ENABLED
          value: "false"
        - name: DISABLE_MACHINE_LEARNING
          value: "false"
        - name: MACHINE_LEARNING_HOST
          value: localhost
        - name: MACHINE_LEARNING_PORT
          value: "3003"
      volumeMounts:
        - name: photos
          mountPath: /usr/src/app/upload

    - name: machine-learning
      image: ghcr.io/immich-app/immich-machine-learning:release
      env:
        - name: DB_HOSTNAME
          value: localhost
        - name: DB_USERNAME
          value: immich
        - name: DB_PASSWORD
          value: "immich_secret_password_change_me"
        - name: DB_DATABASE_NAME
          value: immich
        - name: REDIS_HOSTNAME
          value: localhost
        - name: TYPESENSE_ENABLED
          value: "false"
      volumeMounts:
        - name: photos
          mountPath: /usr/src/app/upload

  volumes:
    - name: postgres-data
      hostPath:
        path: /srv/immich/postgres
        type: DirectoryOrCreate
    - name: postgres-config
      hostPath:
        path: /srv/immich
        type: Directory
    - name: photos
      hostPath:
        path: /mnt/nas/photos
        type: Directory
```

---

### Config Files

#### immich-postgresql.conf
```conf
# PostgreSQL config for Immich with pgvector
listen_addresses = '*'
port = 5432

# Memory (tuned for 32GB RAM system)
shared_buffers = 1GB
effective_cache_size = 24GB
maintenance_work_mem = 512MB
work_mem = 256MB

# Connections
max_connections = 200

# WAL
wal_buffers = 64MB
min_wal_size = 1GB
max_wal_size = 4GB

# Checkpoints
checkpoint_completion_target = 0.9
checkpoint_timeout = 10min

# Logging
log_destination = 'stderr'
logging_collector = off

# pgvector extension
shared_preload_libraries = 'vectorscale'
```

#### searxng-settings.yml
```yaml
# SearXNG settings with JSON support enabled
# See: https://docs.searxng.org/admin/settings/settings.html

use_default_settings: true

general:
  debug: false
  instance_name: "SearXNG"

search:
  safe_search: 0
  autocomplete: 'duckduckgo'
  formats:
    - html
    - json

server:
  secret_key: "30d4cf69b8b8c2d990bd8f778a499fb90f5e337c4a966b911d02152c59aebff9"
  limiter: false

valkey:
  url: redis://localhost:6379/0
```

---

## Scripts

### setup-quadlets.sh

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "=== Creating /srv directory structure ==="

sudo mkdir -p /srv/{linkding,papra,ntfy,peekaping,audiobookshelf,adguardhome,searxng,karakeep,immich}/
sudo mkdir -p /srv/audiobookshelf/{audiobooks,config,metadata,podcasts}
sudo mkdir -p /srv/adguardhome/{work,conf}
sudo mkdir -p /srv/karakeep/{data,meilisearch}
sudo mkdir -p /srv/searxng/valkey
sudo mkdir -p /srv/immich/postgres

sudo chown -R $(id -u):$(id -g) /srv/

echo "=== Setting up NFS mount for photos ==="

sudo mkdir -p /mnt/nas/photos

if ! grep -q "/mnt/nas/photos" /etc/fstab; then
    echo "Adding NFS mount to /etc/fstab..."
    echo "192.168.20.31:/mnt/tank/photos /mnt/nas/photos nfs4 rw,soft,intr,timeo=30,retrans=3,_netdev 0 0" | sudo tee -a /etc/fstab
fi

sudo mount /mnt/nas/photos || echo "Mount may already exist or network not ready"

echo "=== Copying quadlet files ==="

mkdir -p ~/.config/containers/systemd/pods/{searxng,karakeep,immich}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for f in "$SCRIPT_DIR"/containers/*.container; do
    cp "$f" ~/.config/containers/systemd/
done

cp "$SCRIPT_DIR"/pods/searxng/* ~/.config/containers/systemd/pods/searxng/
cp "$SCRIPT_DIR"/pods/karakeep/* ~/.config/containers/systemd/pods/karakeep/
cp "$SCRIPT_DIR"/pods/immich/* ~/.config/containers/systemd/pods/immich/

cp "$SCRIPT_DIR"/config/immich-postgresql.conf /srv/immich/postgresql.conf
cp "$SCRIPT_DIR"/config/searxng-settings.yml /srv/searxng/settings.yml

echo "=== Enabling lingering for user services ==="
sudo loginctl enable-linger $(whoami)

echo "=== Reloading systemd ==="
systemctl --user daemon-reload

echo ""
echo "=== Setup complete! ==="
echo ""
echo "Before starting services, migrate data from old nodes."
echo "See migrate-data.sh for migration script."
echo ""
echo "After migration, start services:"
echo "  systemctl --user enable --now linkding papra ntfy peekaping audiobookshelf adguardhome"
echo "  systemctl --user enable --now searxng karakeep immich"
```

### migrate-data.sh

```bash
#!/usr/bin/env bash
set -euo pipefail

# Migration script - run AFTER stopping swarm stacks on old nodes
# Old nodes: k2=192.168.20.62, k3=192.168.20.63, k4=192.168.20.64

SSH_KEY="$HOME/.ssh/id_ed25519"
SSH_OPTS="-i $SSH_KEY -o IdentitiesOnly=yes -o ConnectTimeout=10"

echo "=== This script should be run AFTER stopping all swarm stacks ==="
echo "On k2, run: docker stack rm linkding papra ntfy peekaping audiobookshelf searxng karakeep immich dozzle"
echo ""
read -p "Have you stopped all swarm stacks? (y/N) " confirm
if [[ "${confirm,,}" != "y" ]]; then
    echo "Aborting. Stop swarm stacks first."
    exit 1
fi

echo ""
echo "=== Extracting Docker named volumes from k2 ==="

ssh $SSH_OPTS crussell@192.168.20.62 << 'EOF'
mkdir -p /home/crussell/volume-backups

# Extract named volumes
for vol in linkding-data papra-data ntfy-data peekaping-data adguardhome-work adguardhome-conf searxng-valkey-data; do
    echo "Extracting $vol..."
    docker run --rm -v $vol:/data -v /home/crussell/volume-backups:/backup alpine tar czf /backup/$vol.tar.gz -C /data . 2>/dev/null || echo "Volume $vol not found or empty"
done
EOF

echo ""
echo "=== Syncing bind mount data from k2 ==="

rsync -avz --progress -e "ssh $SSH_OPTS" \
    crussell@192.168.20.62:/mnt/swarm-data/audiobookshelf/ \
    /srv/audiobookshelf/

rsync -avz --progress -e "ssh $SSH_OPTS" \
    crussell@192.168.20.62:/mnt/swarm-data/karakeep/ \
    /srv/karakeep/data/

rsync -avz --progress -e "ssh $SSH_OPTS" \
    crussell@192.168.20.62:/mnt/swarm-data/karakeep-meilisearch/ \
    /srv/karakeep/meilisearch/

rsync -avz --progress -e "ssh $SSH_OPTS" \
    crussell@192.168.20.62:/mnt/swarm-data/immich/postgres-data/ \
    /srv/immich/postgres/

echo ""
echo "=== Copying volume backups from k2 ==="

rsync -avz --progress -e "ssh $SSH_OPTS" \
    crussell@192.168.20.62:/home/crussell/volume-backups/ \
    /tmp/volume-backups/

echo ""
echo "=== Extracting volume tarballs ==="

for f in /tmp/volume-backups/*.tar.gz; do
    [ -f "$f" ] || continue
    name=$(basename "$f" .tar.gz)
    echo "Extracting $name..."
    
    case $name in
        linkding-data) dest=/srv/linkding/data ;;
        papra-data) dest=/srv/papra/data ;;
        ntfy-data) dest=/srv/ntfy/cache ;;
        peekaping-data) dest=/srv/peekaping/data ;;
        adguardhome-work) dest=/srv/adguardhome/work ;;
        adguardhome-conf) dest=/srv/adguardhome/conf ;;
        searxng-valkey-data) dest=/srv/searxng/valkey ;;
        *) echo "Unknown volume: $name"; continue ;;
    esac
    
    mkdir -p "$dest"
    tar xzf "$f" -C "$dest"
done

echo ""
echo "=== Setting permissions ==="
sudo chown -R $(id -u):$(id -g) /srv/

echo ""
echo "=== Migration complete! ==="
echo ""
echo "Verify data looks correct, then start services:"
echo "  systemctl --user start linkding papra ntfy peekaping audiobookshelf adguardhome"
echo "  systemctl --user start searxng karakeep immich"
```

---

## Caddy Updates

**Status: ✅ COMPLETE** - Caddy migrated from k2 to crussell-srv (2026-02-28)

Caddy now runs as a system-level Quadlet on crussell-srv and handles:
- `*.internal.crussell.io` → Internal services
- `*.crussell.io` → Public services (proxied through Hetzner via Nebula)

**Config Location:** `crussell-srv/caddy/Caddyfile`
**Quadlet:** `/etc/containers/systemd/caddy.container`
**Image:** `localhost/caddy-route53:latest` (custom build with Route53 DNS challenge)

**Public Traffic Flow:**
```
Internet → Hetzner nginx (SSL passthrough) → Nebula → crussell-srv Caddy
```

**Manage:**
```bash
# Reload config
sudo podman exec systemd-caddy caddy reload --config /etc/caddy/Caddyfile

# Validate
sudo podman exec systemd-caddy caddy validate --config /etc/caddy/Caddyfile
```

---

## Migration Checklist

### Phase 1: Prep (no downtime)
- [ ] Build crussell-srv image on new machine
- [ ] Run `just build && just switch` to apply image
- [ ] Reboot into new system
- [ ] Run `setup-quadlets.sh` to create directories and copy quadlet files
- [ ] Verify NFS mount for photos works
- [ ] Do NOT start services yet

### Phase 2: Data Migration (downtime begins)
- [ ] Stop all swarm stacks on k2: `docker stack rm linkding papra ntfy peekaping audiobookshelf searxng karakeep immich dozzle`
- [ ] Wait for all containers to stop
- [ ] Run `migrate-data.sh` to sync all data
- [ ] Verify data copied correctly (check file counts, sizes)

### Phase 3: Start New Services
- [ ] Start single containers: `systemctl --user start linkding papra ntfy peekaping audiobookshelf adguardhome`
- [ ] Verify each service is accessible
- [ ] Start pods: `systemctl --user start searxng karakeep immich`
- [ ] Verify each pod is accessible

### Phase 4: Update Routing
- [ ] Update Caddyfile with new IP (192.168.20.105)
- [ ] Run `./caddy/update_caddy.sh`
- [ ] Test all internal routes work

### Phase 5: Cleanup
- [ ] Keep old nodes offline for backup period
- [ ] Update AGENTS.md with new architecture
- [ ] Decommission old nodes when confident

---

## Post-Maintenance Commands

```bash
# Check all services
systemctl --user list-units --type=service --state=running | grep -E 'linkding|papra|ntfy|peekaping|audiobookshelf|adguardhome|searxng|karakeep|immich'

# Check pod status
podman pods ls

# Check container status
podman ps -a

# View logs
journalctl --user -u immich -f

# Restart a service
systemctl --user restart karakeep

# Stop all services
systemctl --user stop linkding papra ntfy peekaping audiobookshelf adguardhome searxng karakeep immich
```

---

## Notes

- **Rootless podman**: All services run as your user via systemd user units
- **SELinux**: All data in `/srv/` needed `sudo chcon -R -t container_file_t /srv/` for containers to access it
- **Papra AUTH_SECRET**: Must be >= 32 characters, placeholder "papra-auth-secret-change-me" was too short
- **SearXNG settings.yml**: Podman kube play doesn't fully support `subPath` with `hostPath`, had to mount entire directory
- **Immich vectorchord**: Requires vector extension; using `docker.io/pgvector/pgvector:pg16` image
- **Immich pod issue**: Both `server` and `microservices` containers try to bind port 2283 - Podman pods don't handle this well
- **Postgres named volumes**: In rootless podman, need proper permissions or use emptyDir
- **Lingering**: Enabled so services run without you being logged in
- **Chrome sandbox**: Karakeep's chrome container uses `--no-sandbox` with `SYS_ADMIN` capability
- **Secrets**: Currently inline in YAML files. Consider moving to proper secrets management later.
- **Backups**: Update restic backup config to point to `/srv/` paths instead of swarm volumes
