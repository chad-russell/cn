# Nebula Deployment Plan

## Status: ✅ Production - Used for public traffic routing

Nebula now carries production traffic from Hetzner to crussell-srv, replacing Tailscale.

## Architecture

```
                         ┌─────────────────┐
                         │  Hetzner VPS    │
                         │  Lighthouse #2  │
                         │  178.156.171.212│
                         │  nginx passthru │
                         └────────┬────────┘
                                  │ Nebula (10.10.0.2 → 10.10.0.1)
                                  │
                    ┌─────────────▼─────────────┐
                    │      crussell-srv         │
                    │     Lighthouse #1         │
                    │     192.168.20.105        │
                    │     Caddy + Services      │
                    └─────────────┬─────────────┘
                                  │
                    ┌─────────────┼─────────────┐
                    │             │             │
              ┌─────▼─────┐ ┌─────▼─────┐ ┌─────▼─────┐
              │  TrueNAS  │ │    k1     │ │   Phone   │
              │  (NAS)    │ │  (media)  │ │ (roaming) │
              │10.10.0.3  │ │10.10.0.4  │ │10.10.0.11 │
              └───────────┘ └───────────┘ └───────────┘
```

## Network Design

- **Overlay CIDR:** 10.10.0.0/24
- **Lighthouse #1 (crussell-srv):** 10.10.0.1 ✅ DEPLOYED (Fedora Atomic, binary install)
- **Lighthouse #2 (Hetzner):** 10.10.0.2 ✅ DEPLOYED (public lighthouse for roaming)
- **TrueNAS:** 10.10.0.3 ✅ DEPLOYED (TrueNAS SCALE, systemd service)
- **k1 (media):** 10.10.0.4 TODO
- **AI Server:** 10.10.0.5 TODO
- **Laptop:** 10.10.0.10 TODO
- **Phone:** 10.10.0.11 ✅ DEPLOYED (Android app)

## Production Traffic Flow

```
Internet (*.crussell.io)
    │
    ▼
Hetzner nginx (SSL passthrough on :443)
    │
    ▼ stream proxy to 10.10.0.1:443
    │
crussell-srv Nebula (10.10.0.1)
    │
    ▼
crussell-srv Caddy → backend services
```

## CA & Certificate Strategy

### CA Storage (CRITICAL)

**Primary:** Bitwarden (encrypted file attachment)
- Store in a secure note with attachments
- Include: `ca.crt`, `ca.key`
- Add recovery codes and passphrase hints

**Secondary:** Offline backup
- USB drive stored physically secure
- Encrypted with passphrase (different from Bitwarden)

### Certificate Rotation Policy

- CA: 5 year validity
- Host certificates: 1 year validity
- Automate renewal reminders via ntfy

---

## Phase 1: CA Generation (Local Machine)

Do this on your laptop with good entropy:

```bash
# Create working directory (temporary)
mkdir -p ~/nebula-pki && cd ~/nebula-pki

# Download nebula-cert tool
curl -Lo nebula-cert https://github.com/slackhq/nebula/releases/download/v1.9.5/nebula-cert-darwin-arm64
chmod +x nebula-cert

# Generate CA (use a strong passphrase!)
./nebula-cert ca -name "Crussell Nebula CA" -out-crt ca.crt -out-key ca.key -duration 87600h  # 10 years

# Verify
./nebula-cert print -path ca.crt
```

### Generate Lighthouse Certificates

```bash
# Lighthouse #1 - Hetzner
./nebula-cert sign -name "lighthouse-hetzner" -ip "10.10.0.1/24" -groups lighthouse -out-crt lighthouse-hetzner.crt -out-key lighthouse-hetzner.key

# Lighthouse #2 - crussell-srv
./nebula-cert sign -name "lighthouse-crussell-srv" -ip "10.10.0.2/24" -groups lighthouse -out-crt lighthouse-crussell-srv.crt -out-key lighthouse-crussell-srv.key
```

### Generate Host Certificates

```bash
# TrueNAS
./nebula-cert sign -name "truenas" -ip "10.10.0.3/24" -groups servers -out-crt truenas.crt -out-key truenas.key

# k1 media server
./nebula-cert sign -name "k1" -ip "10.10.0.4/24" -groups servers,media -out-crt k1.crt -out-key k1.key

# AI Server
./nebula-cert sign -name "ai-server" -ip "10.10.0.5/24" -groups servers,ai -out-crt ai-server.crt -out-key ai-server.key

# Laptop (roaming)
./nebula-cert sign -name "laptop" -ip "10.10.0.10/24" -groups clients -out-crt laptop.crt -out-key laptop.key

# Phone (roaming)
./nebula-cert sign -name "phone" -ip "10.10.0.11/24" -groups clients -out-crt phone.crt -out-key phone.key
```

### Backup CA to Bitwarden

```bash
# Create encrypted archive
tar czvf - ca.crt ca.key | gpg --symmetric --cipher-algo AES256 -o nebula-ca.tar.gz.gpg

# Upload to Bitwarden:
# 1. Create new Secure Note in Bitwarden
# 2. Title: "Nebula CA - crussell homelab"
# 3. Attach nebula-ca.tar.gz.gpg
# 4. Note the GPG passphrase (use different password than BW login)
# 5. Store passphrase hint in a separate secure note
```

---

## Phase 2: Lighthouse #1 - Hetzner VPS

### Install Nebula

```bash
# SSH to Hetzner VPS
ssh root@<hetzner-ip>

# Download nebula
curl -Lo /usr/local/bin/nebula https://github.com/slackhq/nebula/releases/download/v1.9.5/nebula-linux-amd64
curl -Lo /usr/local/bin/nebula-cert https://github.com/slackhq/nebula/releases/download/v1.9.5/nebula-cert-linux-amd64
chmod +x /usr/local/bin/nebula /usr/local/bin/nebula-cert

# Create config directory
mkdir -p /etc/nebula
```

### Transfer Certificates

```bash
# From your laptop
scp ca.crt lighthouse-hetzner.crt lighthouse-hetzner.key root@<hetzner-ip>:/etc/nebula/
```

### Config: /etc/nebula/config.yaml

```yaml
# Lighthouse #1 - Hetzner VPS
pki:
  ca: /etc/nebula/ca.crt
  cert: /etc/nebula/lighthouse-hetzner.crt
  key: /etc/nebula/lighthouse-hetzner.key

static_host_map:
  # Self (this lighthouse)
  "10.10.0.1": ["<HETZNER_PUBLIC_IP>:4242"]
  # Lighthouse #2 - crussell-srv (LAN IP, only reachable internally)
  "10.10.0.2": ["192.168.20.105:4242"]

lighthouse:
  am_lighthouse: true
  # No hosts to query - we ARE a lighthouse

listen:
  host: 0.0.0.0
  port: 4242

punchy:
  punch: true
  respond: true

tun:
  unsafe_routes:
    # Route to LAN through crussell-srv when on nebula
    - route: 192.168.20.0/24
      via: 10.10.0.2

firewall:
  conntrack:
    tcp_timeout: 120h
    udp_timeout: 3m
    default_timeout: 10m
    max_connections: 100000
  
  outbound:
    - port: any
      proto: any
      host: any
  
  inbound:
    - port: any
      proto: any
      host: any
```

### Systemd Service

```bash
cat > /etc/systemd/system/nebula.service << 'EOF'
[Unit]
Description=Nebula Overlay Network
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
ExecStart=/usr/local/bin/nebula -config /etc/nebula/config.yaml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now nebula
```

### Firewall (Hetzner)

```bash
# Allow nebula UDP port
ufw allow 4242/udp comment 'Nebula mesh VPN'
```

---

## Phase 3: Lighthouse #2 - crussell-srv (Fedora Atomic)

### Install via Quadlet

Create `/etc/containers/systemd/nebula.container`:

```ini
[Unit]
Description=Nebula Overlay Network (Lighthouse)
After=network-online.target
Wants=network-online.target

[Container]
Image=docker.io/slackhq/nebula:1.9.5
ContainerName=nebula
Volume=/etc/nebula:/etc/nebula:Z
PublishPort=4242:4242/udp
# Privileged needed for TUN device
Privileged=true

[Service]
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### Config: /etc/nebula/config.yaml

```yaml
# Lighthouse #2 - crussell-srv
pki:
  ca: /etc/nebula/ca.crt
  cert: /etc/nebula/lighthouse-crussell-srv.crt
  key: /etc/nebula/lighthouse-crussell-srv.key

static_host_map:
  # Lighthouse #1 - Hetzner (always reachable)
  "10.10.0.1": ["<HETZNER_PUBLIC_IP>:4242"]
  # Self
  "10.10.0.2": ["192.168.20.105:4242"]

lighthouse:
  am_lighthouse: true

listen:
  host: 0.0.0.0
  port: 4242

punchy:
  punch: true
  respond: true

firewall:
  conntrack:
    tcp_timeout: 120h
    udp_timeout: 3m
    default_timeout: 10m
    max_connections: 100000
  
  outbound:
    - port: any
      proto: any
      host: any
  
  inbound:
    - port: any
      proto: any
      host: any
```

### Deploy

```bash
# Transfer certs
sudo mkdir -p /etc/nebula
scp ca.crt lighthouse-crussell-srv.crt lighthouse-crussell-srv.key crussell@192.168.20.105:/tmp/
ssh crussell@192.168.20.105 "sudo mv /tmp/ca.crt /tmp/lighthouse-*.crt /tmp/lighthouse-*.key /etc/nebula/"

# Reload quadlets
sudo systemctl daemon-reload
sudo systemctl enable --now nebula
```

---

## Phase 4: Host Configurations

### TrueNAS

TrueNAS has native Nebula support in Apps, or use a custom app:

```yaml
# Use TrueNAS Apps -> Custom App
# Image: slackhq/nebula:1.9.5
# Host Network: true
# Volumes: /etc/nebula -> /etc/nebula
# Privileged: true
```

Config `/mnt/truenas-config/nebula/config.yaml`:

```yaml
pki:
  ca: /etc/nebula/ca.crt
  cert: /etc/nebula/truenas.crt
  key: /etc/nebula/truenas.key

static_host_map:
  "10.10.0.1": ["<HETZNER_PUBLIC_IP>:4242"]
  "10.10.0.2": ["192.168.20.105:4242"]

lighthouse:
  hosts:
    - "10.10.0.1"
    - "10.10.0.2"

listen:
  host: 0.0.0.0
  port: 4242

punchy:
  punch: true

firewall:
  outbound:
    - port: any
      proto: any
      host: any
  inbound:
    - port: any
      proto: any
      host: any
```

### k1 (Media Server) - Fedora Server

```bash
# Binary install (simpler than container for now)
sudo curl -Lo /usr/local/bin/nebula https://github.com/slackhq/nebula/releases/download/v1.9.5/nebula-linux-amd64
sudo chmod +x /usr/local/bin/nebula
sudo mkdir -p /etc/nebula
```

Config `/etc/nebula/config.yaml`:

```yaml
pki:
  ca: /etc/nebula/ca.crt
  cert: /etc/nebula/k1.crt
  key: /etc/nebula/k1.key

static_host_map:
  "10.10.0.1": ["<HETZNER_PUBLIC_IP>:4242"]
  "10.10.0.2": ["192.168.20.105:4242"]

lighthouse:
  hosts:
    - "10.10.0.1"
    - "10.10.0.2"

listen:
  host: 0.0.0.0
  port: 4242

punchy:
  punch: true

firewall:
  outbound:
    - port: any
      proto: any
      host: any
  inbound:
    - port: any
      proto: any
      host: any
```

### AI Server

Same as k1 - binary install with appropriate cert.

### Laptop (macOS)

```bash
# Install via Homebrew
brew install nebula

# Create config
sudo mkdir -p /usr/local/etc/nebula
sudo cp ca.crt laptop.crt laptop.key /usr/local/etc/nebula/
```

Config `/usr/local/etc/nebula/config.yaml`:

```yaml
pki:
  ca: /usr/local/etc/nebula/ca.crt
  cert: /usr/local/etc/nebula/laptop.crt
  key: /usr/local/etc/nebula/laptop.key

static_host_map:
  "10.10.0.1": ["<HETZNER_PUBLIC_IP>:4242"]
  "10.10.0.2": ["192.168.20.105:4242"]

lighthouse:
  hosts:
    - "10.10.0.1"
    - "10.10.0.2"

listen:
  host: 0.0.0.0
  port: 4242

punchy:
  punch: true

# No inbound on roaming clients by default
firewall:
  outbound:
    - port: any
      proto: any
      host: any
  inbound:
    - port: any
      proto: icmp
      host: any
```

```bash
# LaunchAgent for auto-start
sudo nebula -config /usr/local/etc/nebula/config.yaml
```

### Phone (iOS/Android)

1. Download Nebula app from App Store / Play Store
2. Transfer `ca.crt`, `phone.crt`, `phone.key` via AirDrop or secure method
3. Import into app
4. Configure lighthouse IPs
5. Enable VPN on demand (optional)

---

## Phase 5: Testing Checklist

```bash
# From crussell-srv, ping Hetzner lighthouse
ping 10.10.0.1

# From laptop (external network), ping crussell-srv
ping 10.10.0.2

# Verify full mesh
for ip in 10.10.0.{1,2,3,4,5}; do
  echo -n "$ip: "
  ping -c1 -W1 $ip >/dev/null && echo "UP" || echo "DOWN"
done

# Test LAN routing through crussell-srv (when on nebula from external)
ping 192.168.20.31  # TrueNAS LAN IP

# Disconnect internet, verify LAN hosts still communicate
# (lighthouse #2 handles discovery)
```

---

## Maintenance

### Certificate Renewal (Yearly)

```bash
# Restore CA from Bitwarden
gpg -d nebula-ca.tar.gz.gpg | tar xzvf -

# Renew a host cert
./nebula-cert sign -name "k1" -ip "10.10.0.4/24" -groups servers,media \
  -out-crt k1-new.crt -out-key k1-new.key -ca-crt ca.crt -ca-key ca.key

# Deploy new cert, restart nebula
```

### Add New Host

```bash
./nebula-cert sign -name "newhost" -ip "10.10.0.X/24" -groups servers \
  -out-crt newhost.crt -out-key newhost.key

# Distribute ca.crt, newhost.crt, newhost.key
# Use standard host config template
```

---

## Rollback Plan

Keep Tailscale running during migration. Each host can have both:
- Nebula: 10.10.0.0/24
- Tailscale: 100.x.x.x

Once Nebula is stable, decommission Tailscale.

---

## Files to Store in This Repo

```
cn/nebula/
├── DEPLOYMENT.md (this file)
├── configs/
│   ├── lighthouse-hetzner.yaml
│   ├── lighthouse-crussell-srv.yaml
│   └── host-template.yaml
├── quadlets/
│   └── nebula.container (for crussell-srv)
└── scripts/
    └── gen-certs.sh (helper for future cert generation)
```

**DO NOT COMMIT:** *.crt, *.key, ca.key (only ca.crt could be committed if desired)
