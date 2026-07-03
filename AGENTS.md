# AGENTS.md

Root navigation and operating guide for agents working in this personal infrastructure repository.

**Read this first.** The repository uses a unified Nix flake. Prefer the Nix configuration and live host state over older docs when facts disagree.

Last validated via SSH: **2026-05-06**.

## Ground Rules for Agents

1. **Source of truth:** `flake.nix`, `hosts/*/*.nix`, `modules/*.nix`, and live host state are authoritative.
2. **Use Nix for host config changes** whenever possible. Deploy with `nix run .#deploy -- <host>`.
3. **Caddy route source lives in `hosts/bees/caddy/`** and is installed to `/etc/caddy` by the `hosts/bees/caddy.nix` module; deploy `bees`, then validate/reload Caddy.
4. **Never commit plaintext secrets.** Existing plaintext secret-like files should be treated carefully; do not print or copy their contents into docs, logs, or chat unless explicitly necessary.
5. **When unsure, verify live state over SSH** using the SSH notes below.

## Current Repository Map

```text
.
├── flake.nix                  # Unified NixOS flake: hosts, deploy/install apps
├── flake.lock
├── AGENTS.md                  # This guide
├── hosts/
│   ├── bee/                   # Beelink mini PC: dev stack (Gloo) + Nebula lighthouse
│   │   ├── configuration.nix
│   │   ├── buildspace.nix
│   │   └── gloo/ buildspace/
│   ├── bees/                  # Production server: all shared + media + ingress services
│   │   ├── configuration.nix
│   │   ├── caddy.nix + caddy/ (Caddyfile, routes)
│   │   ├── media-services.nix
│   │   ├── immich.nix
│   │   ├── ntfy.nix, searxng.nix, datenight.nix
│   │   ├── hub-services.nix, linkding.container, papra.container, open-webui.container
│   │   ├── prometheus.nix, homelab-monitor.nix
│   │   └── disk-config.nix
│   ├── homeassistant/         # HAOS operational docs + helper scripts + Nebula add-on
│   │   ├── addons/nebula/     # Local HAOS add-on: Nebula VPN client
│   │   ├── scripts/           # Deploy, SSH, supervisor helpers
│   │   └── README.md
│   ├── misc/                  # HP Z820 workstation (temporary backup target)
│   └── thinkpad/              # `think` laptop NixOS + home-manager config
├── modules/
│   ├── base-server.nix        # Shared server baseline: user, SSH, networkd, packages, GC, NFS client
│   ├── server-shell.nix       # Shared zsh/CLI setup for servers
│   ├── nebula-client.nix      # Shared Nebula client defaults (used by servers + think)
│   ├── nebula-hosts.nix       # /etc/hosts entries for Nebula overlay names
│   ├── fzf-history-widget.zsh # Shared fzf Ctrl+R widget for zsh
│   └── hub-disk-config.nix    # Beelink/bee btrfs disk layout
├── nebula/
│   ├── configs/               # Nebula config templates
│   ├── pki/                   # Nebula CA/certs and age-encrypted private keys
│   └── scripts/               # Nebula helper binaries/scripts
├── secrets/                   # Agenix secrets used by server modules
```

## Current Architecture

```
                              Internet
                                  │
                                  ▼
                ┌──────────────────────────────────┐
                │ gateway / Hetzner VPS             │
                │ 178.156.171.212 / NixOS 25.11     │
                │ Caddy: *.crussell.io TLS ingress  │
                │   (HTTP-01) → backends over Nebula│
                │ Nebula lighthouse+relay 10.10.0.2 │
                └───────────────┬──────────────────┘
                                │ Nebula to 10.10.0.6 / 10.10.0.51
                ┌───────────────┴──────────────────┐
                ▼                                  ▼
   ┌──────────────────────────┐   ┌──────────────────────────┐
   │ bees — production server │   │ bee — dev + Nebula LH    │
   │ 192.168.20.41            │   │ 192.168.20.105           │
   │ Nebula 10.10.0.6         │   │ Nebula 10.10.0.12        │
   │                          │   │ Nebula LH 10.10.0.1      │
   │ AMD Ryzen AI MAX+ 395    │   │ AMD Ryzen 7 7840HS       │
   │ 16C/32T, ~62 GB RAM     │   │ 8C/16T, 27 GB RAM        │
   │ 2 TB NVMe, dual 10GbE   │   │ 1 TB NVMe, 1 GbE         │
   │                          │   │                          │
   │ ALL PRODUCTION SERVICES: │   │ SERVICES:                │
   │  Caddy (*.internal TLS)  │   │  Nebula lighthouse       │
   │  ntfy, SearXNG, datenight│   │  Gloo dev stack          │
   │  linkding, papra         │   │  Buildspace (disabled)   │
   │  open-webui              │   │                          │
   │  Jellyfin, Sonarr,       │   │                          │
   │  Radarr, Prowlarr,       │   │                          │
   │  qBittorrent, Jellyseerr │   │                          │
   │  Immich (server + ML)    │   │                          │
   │  Prometheus, monitoring  │   │                          │
   └──────────┬───────────────┘   └──────────┬───────────────┘
              │ NFS (10GbE)                   │ NFS
              ▼                                ▼
    ┌─────────────────┐            ┌─────────────────┐
    │ nas / NixOS      │            │ nas / NixOS     │
    │ 192.168.20.31   │            │ 192.168.20.31   │
    │ NFS: media,     │            │ NFS: backups    │
    │ photos, backups │            └─────────────────┘
    └─────────────────┘

Also on LAN: homeassistant / HAOS at 192.168.20.51, Nebula 10.10.0.51.
Laptop: think / NixOS 25.11, configured under `hosts/thinkpad/`.
```

## Machine Registry

| Host            | LAN IP            | Nebula IP                             | OS          | Config                               | Purpose / services                                                                                                                                                                                 |
| --------------- | ----------------- | ------------------------------------- | ----------- | ------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `bees`          | `192.168.20.41`   | `10.10.0.6`                           | NixOS 25.11 | `hosts/bees/`                        | Production server: Caddy (**internal `*.internal.crussell.io` only**), ntfy, SearXNG, datenight, linkding, papra, open-webui, Jellyfin, Sonarr, Radarr, Prowlarr, qBittorrent, Jellyseerr, Immich. |
| `bee`           | `192.168.20.105`  | `10.10.0.12` + lighthouse `10.10.0.1` | NixOS 25.11 | `hosts/bee/`                         | Dev server: Gloo stack, Nebula lighthouse.                                                                                                                                                         |
| `think`         | varies            | `10.10.0.10`                          | NixOS 25.11 | `hosts/thinkpad/`                    | Laptop with home-manager, niri, Noctalia, Podman, dev tools.       |
| `nas`           | `192.168.20.31`   | `10.10.0.3`                           | NixOS 25.11 | `hosts/nas/`                         | NFS storage: media, photos, backups. Btrfs RAID1, btrfs-maintenance.                                                                                                                               |
| `homeassistant` | `192.168.20.51`   | `10.10.0.51`                          | HAOS        | `hosts/homeassistant/` add-on + docs | Home Assistant OS. Nebula via local add-on.                                                                                                                                                        |
| `gateway`       | `178.156.171.212` | `10.10.0.2`                           | NixOS 25.11 | `hosts/gateway/`                     | Hetzner Cloud VPS: **Caddy public TLS ingress** for `*.crussell.io` (HTTP-01, reverse-proxies to backends over Nebula). Nebula lighthouse/relay.                                                   |

## SSH Access

Use the ed25519 key and force identities when automating:

```bash
ssh -o IdentitiesOnly=yes <user>@<host>
```

**Prefer Nebula overlay IPs over LAN IPs** — Nebula is always reachable regardless of physical network location.

Active targets:

```bash
# Production server (deployed as crussell with sudo)
ssh -o IdentitiesOnly=yes crussell@10.10.0.6          # bees (Nebula)
ssh -o IdentitiesOnly=yes crussell@192.168.20.41      # bees (LAN fallback)

# Dev server + lighthouse (deployed as crussell with sudo)
ssh -o IdentitiesOnly=yes crussell@10.10.0.12         # bee (Nebula)
ssh -o IdentitiesOnly=yes crussell@192.168.20.105     # bee (LAN fallback)

# Hetzner gateway
ssh -o IdentitiesOnly=yes root@10.10.0.2              # gateway (Nebula)
ssh -o IdentitiesOnly=yes root@178.156.171.212        # gateway (public IP)
```

Home Assistant SSH: see `hosts/homeassistant/README.md` and helper scripts under `hosts/homeassistant/scripts/`.

## Nix Operations

Available flake hosts:

```bash
nix flake show
# NixOS configs: think, bee, bees, misc
```

Deploy active machines:

```bash
# Production server
nix run .#deploy -- bees

# Dev server + lighthouse
nix run .#deploy -- bee

# Both
nix run .#deploy -- bee bees

# Laptop, local rebuild
nix run .#deploy -- think
```

Install/wipe a new host with nixos-anywhere:

```bash
# WARNING: destructive
nix run .#install -- bees 192.168.20.41
nix run .#install -- bee 192.168.20.105
```

Useful validation before deploy:

```bash
# Fast eval check
nix eval .#nixosConfigurations.bees.config.networking.hostName --raw

# Build without switching
nix build .#nixosConfigurations.bees.config.system.build.toplevel
```

## Service Operations by Host

### bees — Production server (all workloads)

Source files:

- `hosts/bees/configuration.nix`
- `hosts/bees/caddy.nix` + `hosts/bees/caddy/` (Caddyfile, routes)
- `hosts/bees/media-services.nix` — Jellyfin, Sonarr, Radarr, Prowlarr, qBittorrent, Jellyseerr
- `hosts/bees/immich.nix` — Immich server + ML
- `hosts/bees/ntfy.nix`, `searxng.nix`, `datenight.nix`
- `hosts/bees/hub-services.nix` + `*.container` — linkding, papra, open-webui
- `hosts/bees/prometheus.nix` — Prometheus monitoring
- `hosts/bees/homelab-monitor.nix` — AI-powered infrastructure monitoring

Live systemd services:

- `nebula@homelab.service` — service identity `10.10.0.6`
- `caddy.service` — Podman Quadlet, container name `systemd-caddy`
- `ntfy-sh.service` — port `8090`
- `searx.service` + `redis-searx.service` — SearXNG on port `8888`
- `datenight.service` — port `7890`
- `linkding.service` — publishes `30080 -> 9090`
- `papra.service` — publishes `30083 -> 1221`
- `open-webui.service` — publishes `30088 -> 8080`
- `jellyfin.service` — `8096`
- `sonarr.service` — `8989`
- `radarr.service` — `7878`
- `prowlarr.service` — `9696`
- `jellyseerr.service` — `5055`
- `qbittorrent.service` — Web UI `8080`, torrenting `51413`
- `immich-server.service` — `2283`
- `immich-machine-learning.service`
- `postgresql.service` — Immich DB
- `redis-immich.service`

Storage:

- `/mnt/media` from `192.168.20.31:/pool/media`
- `/mnt/photos` from `192.168.20.31:/pool/photos`
- `/mnt/backups` automount from `192.168.20.31:/pool/backups`

Useful checks:

```bash
ssh -o IdentitiesOnly=yes crussell@192.168.20.41
systemctl status caddy ntfy-sh searx datenight linkding papra open-webui jellyfin sonarr radarr prowlarr jellyseerr qbittorrent immich-server
podman ps
journalctl -u caddy -f
```

#### Public ingress (gateway)

Public `*.crussell.io` traffic is handled by **Caddy on the gateway**
(`hosts/gateway/caddy.nix`), which terminates TLS (Let's Encrypt HTTP-01) and
reverse-proxies to each backend over Nebula. Bees is **no longer** on the
public path — see the gateway section above.

#### Internal Caddy routes (bees)

Bees's Caddy (`hosts/bees/caddy/Caddyfile`) handles **only**
`*.internal.crussell.io` (Route53 DNS-challenge wildcard cert). Public DNS
resolves `*.internal.crussell.io` → `10.10.0.6` (bees Nebula), so internal
clients reach bees directly over the overlay, bypassing the gateway.

Internal route snippets live under `hosts/bees/caddy/routes/internal/`:

- `hub-services.caddy` — linkding, papra, ntfy, SearXNG, open-webui
- `media.caddy` — qBittorrent, Sonarr, Radarr, Prowlarr, Jellyseerr, Jellyfin internal
- `gloo.caddy` — Gloo dev stack on `bee`
- `buildspace.caddy` — Buildspace dev stack on `bee`

#### Updating Caddy Routes

Edit repo source files, deploy `bees` to update `/etc/caddy`, then validate and reload:

```bash
# from repo root
nix run .#deploy -- bees

ssh -o IdentitiesOnly=yes crussell@192.168.20.41 '
  sudo podman exec systemd-caddy caddy validate --config /etc/caddy/Caddyfile &&
  sudo podman exec systemd-caddy caddy reload --config /etc/caddy/Caddyfile
'
```

Caddy's Route53 DNS challenge credentials are managed via agenix (`secrets/aws-env.age`), decrypted at runtime to `/run/agenix/aws-env`. **Bees uses this only for the internal `*.internal.crussell.io` wildcard cert**; the gateway's public ingress uses HTTP-01 and needs no credentials.

### bee — Dev server + Nebula lighthouse

Source files:

- `hosts/bee/configuration.nix`
- `hosts/bee/gloo/` — override files, skill
- `hosts/bee/buildspace.nix` — podman, docker-compose, user linger

Running services:

- `nebula@homelab.service` — `10.10.0.12`
- `nebula@lighthouse.service` — local lighthouse `10.10.0.1`, UDP `4243`
- Gloo devcontainers (plain `podman compose` in each repo's `.devcontainer/`)

Gloo development uses **repo devcontainers** directly — each Gloo repo has its own `.devcontainer/docker-compose.yml`. No wrappers, no glooctl. Run `podman compose` with override files for port publishing and rootless podman UID mapping.

Products: `polymer`, `gpl`, `hummingbird`, `storyhub`. Hummingbird and storyhub share the same devcontainer.

Operate Gloo over SSH:

```bash
ssh -o IdentitiesOnly=yes crussell@10.10.0.12
cd ~/Gloo/360-polymer/.devcontainer
podman compose -f docker-compose.yml -f ~/.config/gloo/overrides/polymer.yml up -d --build
podman compose exec -d app pnpm dev
podman compose logs -f app
```

See `hosts/bee/gloo/SKILL.md` for full documentation.

Deploy uses `crussell@192.168.20.105 --sudo` per `flake.nix`.

### gateway — Hetzner Cloud VPS (public ingress)

Source files:

- `hosts/gateway/configuration.nix`
- `hosts/gateway/caddy.nix` — native NixOS Caddy, public TLS termination
- `hosts/gateway/disk-config.nix`

NixOS 25.11 on Hetzner Cloud x86_64 (legacy BIOS boot, GRUB).

- Public IP `178.156.171.212` (DHCP from Hetzner Cloud)
- Nebula `10.10.0.2` (lighthouse + relay, UDP `4242`)
- **Caddy terminates TLS for all `*.crussell.io` public hostnames** (native
  NixOS Caddy, Let's Encrypt HTTP-01 — no Route53, **no secrets on the
  VPS**) and reverse-proxies to each backend over the Nebula overlay.
  This replaced the old nginx TCP-passthrough → bees design, which made bees
  a single point of failure for all public routes.
- Public DNS: `*.crussell.io` → `178.156.171.212` (gateway).
  Internal DNS: `*.internal.crussell.io` → `10.10.0.6` (bees) — bypasses the
  gateway entirely.
- Firewall: TCP `22`, `80`, `443`; UDP `4242`

Public routes (gateway Caddy → backend over Nebula):

| Public hostname             | Backend                                                                                  |
| --------------------------- | ---------------------------------------------------------------------------------------- |
| `homeassistant.crussell.io` | `10.10.0.51:8123` (HA, direct; X-Forwarded-For stripped — see `hosts/gateway/caddy.nix`) |
| `jellyfin.crussell.io`      | `10.10.0.6:8096`                                                                         |
| `photos.crussell.io`        | `10.10.0.6:2283`                                                                         |
| `datenight.crussell.io`     | `10.10.0.6:7890`                                                                         |
| `glooai.crussell.io`        | `10.10.0.6:4637`                                                                         |

> To add/change a public route, edit `hosts/gateway/caddy.nix` and `nix run .#deploy -- gateway`. Adding a new hostname requires it to resolve to the gateway (covered by the `*.crussell.io` wildcard) and Caddy auto-issues its cert on first request via HTTP-01.

- SSH password auth disabled (public-facing)

Nebula certs at `/etc/nebula/{ca.crt,host.crt,host.key}` (deployed manually).
PKI source: `nebula/pki/hetzner-lighthouse.{crt,key.age}`.

Deploy:

```bash
nix run .#deploy -- gateway
```

Install/rebuild (destructive — same IP preserved):

```bash
nix run .#install -- gateway
```

Use `ssh -o IdentitiesOnly=yes root@178.156.171.212` to verify.

## Nebula VPN

Nix-managed server defaults live in:

- `modules/nebula-client.nix` — shared client defaults for all NixOS hosts (servers + thinkpad)
- `modules/nebula-hosts.nix` — `/etc/hosts` entries for overlay names
- per-host overrides in `hosts/*/configuration.nix`

Current overlay host entries from `modules/nebula-hosts.nix`:

| Nebula IP    | Name / role                                 |
| ------------ | ------------------------------------------- |
| `10.10.0.1`  | `nebula-lh` — local lighthouse on `bee`     |
| `10.10.0.2`  | `nebula-hetzner` — Hetzner lighthouse/relay |
| `10.10.0.3`  | `nas`                                       |
| `10.10.0.6`  | `bees` — production server                  |
| `10.10.0.11` | `misc`                                      |
| `10.10.0.12` | `bee` — dev server                          |
| `10.10.0.10` | `think` — laptop                            |

For NixOS hosts, certs are expected at:

```text
/etc/nebula/ca.crt
/etc/nebula/host.crt
/etc/nebula/host.key
```

`bee` also has local lighthouse certs at:

```text
/etc/nebula-lh/ca.crt
/etc/nebula-lh/host.crt
/etc/nebula-lh/host.key
```

Nebula PKI files:

- Public certs: `nebula/pki/*.crt` (safe to commit)
- Encrypted private keys: `nebula/pki/*.key.age` (safe to commit if correctly encrypted)
- Plain private keys: `nebula/pki/*.key` (gitignored by `nebula/.gitignore`; never commit)
- CA private key: `nebula/pki/ca.key.age` is critical infrastructure; handle with extra care.

Decrypt Nebula key material with the SSH ed25519 key when needed:

```bash
age -d -i ~/.ssh/id_ed25519 nebula/pki/bees.key.age > /tmp/bees.key
```

## Secrets

Agenix and age are both used:

- `secrets/*.age` — server secrets (aws-env, openrouter-api-key, restic passwords, S3 credentials).
- `hosts/thinkpad/secrets/*.age` — home-manager/laptop secrets.
- `nebula/pki/*.key.age` — Nebula private keys encrypted to the SSH ed25519 public key.

Gloo env files (`.env` / `.env.local`) are gitignored and backed by 1Password — NOT managed by Nix or agenix.

Rules:

1. Prefer encrypted `*.age` files for new secrets.
2. Do not add plaintext `*.env`, raw keys, tokens, or passwords.
3. If a plaintext secret-like file is already tracked, avoid expanding its usage; consider migrating it to agenix in a separate explicit change.

## Adding or Updating Services

### Preferred: native NixOS module

1. Add a `hosts/<host>/<service>.nix` module or edit the host config.
2. Import it from `hosts/<host>/configuration.nix`.
3. Open firewall ports declaratively with `networking.firewall.allowedTCPPorts` / `allowedUDPPorts` if needed.
4. Deploy with `nix run .#deploy -- <host>`.
5. Verify with `systemctl status`, `journalctl`, `podman compose logs`, and HTTP checks.

### System Podman Quadlet on bees

Existing examples: `linkding.container`, `papra.container`, `open-webui.container`, `caddy/caddy.container`.

1. Add a `.container` file under `hosts/bees/` or `hosts/bees/caddy/`.
2. Add an `environment.etc."containers/systemd/<name>.container"` entry in a Nix module.
3. Ensure data directories/volumes in activation scripts if needed.
4. Deploy `bees` and start/restart `<name>.service`.
5. Add Caddy route if externally reachable.

### Caddy route change

1. Edit `hosts/bees/caddy/Caddyfile` for public routes or `hosts/bees/caddy/routes/internal/*.caddy` for internal routes.
2. Deploy `bees` so Nix updates `/etc/caddy`.
3. Validate and reload Caddy inside the `systemd-caddy` container.
4. Test with `curl -I https://<host>` from a network that can resolve/reach the domain.

## Archived / Deprecated Context

Older docs may refer to:

- `servers/hub/quadlets/...`
- `servers/hub/caddy/...`
- `servers/hub/dev-stacks/...`
- `servers/media/...`
- `brunch/config/...`
- host name `hub` for what is now `bees`

Treat those as historical unless the files still exist and the current Nix config agrees.
