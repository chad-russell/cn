# Beszel Agent on TrueNAS

This directory contains the configuration for running Beszel Agent on your TrueNAS server.

## Prerequisites

1. TrueNAS must have Docker enabled and running
2. TrueNAS IP: `192.168.20.31`
3. Beszel Hub must be running on k4 (`192.168.20.64:8090`)

## Deployment Steps

### Step 1: Add TrueNAS to Beszel Hub

1. Access `https://beszel.internal.crussell.io` in your browser
2. Login with your credentials
3. Click **Add System** button (top right)
4. Enter:
   - **Name**: `nas`
   - **Host/IP**: `192.168.20.31`
   - **Port**: `45876` (default)
5. Click **Add System**
6. **Copy the generated TOKEN** from the system details

### Step 2: Update Docker Compose File

1. Open `docker-compose.yml` in this directory
2. Replace `<GENERATE_TOKEN_FROM_BESZEL_UI>` with the actual token from Step 1
3. Save the file

### Step 3: Deploy to TrueNAS

There are two ways to deploy:

**Option A: Via TrueNAS Web UI**
1. Open TrueNAS web UI → **Apps** → **Settings** → **Compose**
2. Click **Add Settings** (or similar)
3. Name: `beszel-agent`
4. Select the `docker-compose.yml` file from this directory
5. Click **Save** and **Deploy**

**Option B: Via SSH (faster for updates)**
```bash
# Create directory on TrueNAS
ssh root@192.168.20.31 "mkdir -p /mnt/tank/docker/beszel"

# Copy files to TrueNAS
scp /home/crussell/Code/cn/truenas/docker-compose.yml root@192.168.20.31:/mnt/tank/docker/beszel/

# SSH into TrueNAS and deploy
ssh root@192.168.20.31 "cd /mnt/tank/docker/beszel && docker compose up -d"
```

### Step 4: Verify Connection

1. In Beszel web UI, check if the NAS system shows as **Connected**
2. Check logs: `ssh root@192.168.20.31 "docker logs -f beszel-agent"`

## Troubleshooting

**Agent shows 401 error:**
- Verify TOKEN in docker-compose.yml matches what's in Beszel UI
- Verify KEY matches exactly (copy/paste from this file)
- Verify HUB_URL is correct: `http://192.168.20.64:8090`

**Agent cannot connect to hub:**
- Check network connectivity: `ssh root@192.168.20.31 "ping 192.168.20.64"`
- Verify TrueNAS firewall allows connections on port 45876

**Docker socket errors:**
- Verify TrueNAS Docker is enabled
- Check `/var/run/docker.sock` is accessible on TrueNAS

## Monitored Storage

This configuration monitors:
- **Tank pool**: `/mnt/tank`
- **Photos**: `/mnt/tank/photos`
- **Backups**: `/mnt/tank/backups`

To add more storage, add additional volume mounts:
```yaml
volumes:
  - /mnt/tank/moredata:/extra/moredata:ro
```

## Updating the Agent

**Via SSH (recommended):**
```bash
ssh root@192.168.20.31 "cd /mnt/tank/docker/beszel && docker compose pull && docker compose up -d"
```

**Via TrueNAS UI:**
1. Open TrueNAS → Apps → Installed Apps → beszel-agent
2. Click **Update** → **Pull latest image**
3. Click **Save**

## Removing the Agent

**Via SSH:**
```bash
ssh root@192.168.20.31 "cd /mnt/tank/docker/beszel && docker compose down"
```

**Via TrueNAS UI:**
1. Open TrueNAS → Apps → Installed Apps → beszel-agent
2. Click **Stop** → **Delete**
