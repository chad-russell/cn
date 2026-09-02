# AGENTS.md

Root navigation and operating guide for agents working in this personal infrastructure repository.

**Read this first.** The repository uses a unified Nix flake. Prefer the Nix configuration and live host state over older docs when facts disagree.

Last validated via SSH: **2026-08-10**.

## Ground Rules for Agents

1. **Source of truth:** `flake.nix`, `hosts/*/*.nix`, `modules/*.nix`, and live host state are authoritative.
2. **Use Nix for host config changes** whenever possible. Deploy with `nix run .#deploy -- <host>` run **from `bees`** (the deploy origin — see [Nix Operations](#nix-operations)).
3. **Caddy route source lives in `hosts/bees/caddy/`** and is installed to `/etc/caddy` by the `hosts/bees/caddy.nix` module; deploy `bees`, then validate/reload Caddy.
4. **Never commit plaintext secrets.** Existing plaintext secret-like files should be treated carefully; do not print or copy their contents into docs, logs, or chat unless explicitly necessary.
5. **When unsure, verify live state over SSH** using the SSH notes below.

## Current Repository Map

```text
.
├── flake.nix                  # Unified NixOS flake: hosts, deploy/install apps, checks
├── flake.lock
├── treefmt.toml               # nixfmt-classic formatter config (run: treefmt)
├── AGENTS.md                  # This guide
├── hosts/
│   ├── bee/                   # Beelink mini PC: dev server + Nebula lighthouse
│   │   ├── configuration.nix
│   │   ├── disk-config.nix
│   │   ├── backup.nix         # Restic backup to S3
│   │   ├── tailscale.nix      # On-demand Tailscale (not default-on)
│   │   ├── buzz-relay.nix     # Self-hosted Buzz relay pod (6 containers)
│   │   ├── buzz-relay.pod     # Podman pod definition
│   │   ├── buzz-*.container   # Relay containers (relay, postgres, redis, minio, pair-relay)
│   │   └── dev-quadlets.nix   # Dev environment stacks + README
│   │       └── dev-quadlets/  # gpl, polymer, buildspace (container + volume + network per project)
│   ├── bees/                  # Production server: all shared + media + ingress services
│   │   ├── configuration.nix
│   │   ├── disk-config.nix
│   │   ├── caddy.nix + caddy/ (Caddyfile, routes, caddy.container)
│   │   │   └── routes/internal/ (services.caddy, media.caddy, beszel.caddy)
│   │   ├── media-services.nix
│   │   ├── immich.nix + immich-backup.nix
│   │   ├── beszel.nix         # Beszel monitoring hub
│   │   ├── ntfy.nix, datenight.nix
│   │   ├── services.nix
│   │   ├── backup.nix         # Restic backup to S3
│   │   └── *.container        # linkding, papra, jellyfin, jellyseerr, sonarr, radarr, prowlarr, qbittorrent
│   ├── gateway/               # Hetzner Cloud VPS: public TLS ingress
│   │   ├── configuration.nix
│   │   ├── caddy.nix          # Native NixOS Caddy (HTTP-01, no secrets)
│   │   └── disk-config.nix
│   ├── nas/                   # NFS storage server
│   │   ├── configuration.nix
│   │   ├── disk-config.nix
│   │   ├── nfs-exports.nix
│   │   ├── samba.nix
│   │   └── btrfs-maintenance.nix
│   ├── homeassistant/         # HAOS operational docs + helper scripts + Nebula add-on
│   │   ├── addons/nebula/     # Local HAOS add-on: Nebula VPN client
│   │   ├── incidents/         # Post-mortem notes
│   │   ├── scripts/           # Deploy, SSH, supervisor helpers
│   │   └── README.md
│   └── thinkpad/              # `think` laptop: custom Bluefin image (NOT NixOS deploy target)
│       ├── Justfile            # `cjust` task runner (entry point for all maintenance)
│       ├── README.md           # Comprehensive thinkpad-specific guide
│       ├── host-image/        # bootc Containerfile + build/switch/upgrade scripts
│       ├── nebula/            # Nebula VPN (rootful podman quadlet)
│       ├── backup/            # Restic S3 backup quadlets + timers
│       ├── bubblebox/         # Host's bubblebox profile.toml
│       ├── bubblebox/files/  # Host-native dotfiles (managed by bubblebox apply)
│       ├── bubblebox/units/  # User systemd units (managed by bubblebox apply)
│       ├── gloo/              # Gloo dev quadlets (local copies)
│       ├── buildspace/        # Buildspace dev stack
│       ├── tailscale/         # On-demand Tailscale container
│       └── wycliffe-vpn/      # GlobalProtect VPN wrapper
├── lib/
│   └── host-meta.nix          # Single source of truth: host → IPs + deploy metadata
├── modules/
│   ├── base-server.nix        # Shared server baseline: user, SSH, networkd, packages, GC, NFS client
│   ├── server-shell.nix       # Shared zsh/CLI setup for servers
│   ├── server-home.nix        # Home-manager config for crussell on all servers
│   ├── nebula-client.nix      # Shared Nebula client defaults (used by servers)
│   ├── nebula-hosts.nix       # /etc/hosts entries for Nebula overlay names (generated from lib/host-meta.nix)
│   ├── dsh.nix                # DeepSeek Harness (dsh) web UI on bee
│   ├── beszel-agent.nix       # Beszel agent (default-on for importers)
│   ├── restic-backup.nix      # Shared restic backup job builder
│   ├── btrfs-snapshots.nix    # Btrfs snapshot management
│   ├── buzz-harness.nix       # Buzz agent harness (disabled on bee, replaced by Hermes)
│   ├── freshness-checks.nix   # Periodic health checks with ntfy alerting
│   └── fzf-history-widget.zsh # Shared fzf Ctrl+R widget for zsh
├── nebula/
│   ├── configs/               # Nebula config templates
│   ├── pki/                   # Nebula CA/certs and age-encrypted private keys
│   └── scripts/               # Nebula helper binaries/scripts
├── pkgs/
│   └── buzz/                  # Buzz CLI (Rust, built against pinned toolchain)
├── secrets/                   # Agenix secrets used by server modules
└── treefmt.toml               # nixfmt-classic formatter config
```

## Current Architecture

```
                              Internet
                                  │
                                  ▼
                ┌────────────────────────────────────┐
                │ gateway / Hetzner VPS              │
                │ 178.156.171.212 / NixOS 25.11      │
                │ Caddy: *.crussell.io TLS ingress   │
                │   (HTTP-01) → backends over Nebula │
                │ Nebula lighthouse+relay 10.10.0.2  │
                └───────────────┬────────────────────┘
                                │ Nebula to 10.10.0.6 / 10.10.0.51
                ┌───────────────┴──────────────────┐
                ▼                                  ▼
   ┌──────────────────────────┐   ┌──────────────────────────┐
   │ bees — production server │   │ bee — dev + Nebula LH    │
   │ 192.168.20.41            │   │ 192.168.20.105           │
   │ Nebula 10.10.0.6         │   │ Nebula 10.10.0.12        │
   │                          │   │ Nebula LH 10.10.0.1      │
   │ AMD Ryzen AI MAX+ 395    │   │ AMD Ryzen 7 7840HS       │
   │ 16C/32T, ~62 GB RAM      │   │ 8C/16T, 27 GB RAM        │
   │ 2 TB NVMe, dual 10GbE    │   │ 1 TB NVMe, 1 GbE         │
   │                          │   │                          │
   │ ALL PRODUCTION SERVICES: │   │ SERVICES:                │
   │   Caddy (*.internal TLS) │   │  Nebula lighthouse       │
   │    ntfy, datenight       │   │                          │
   │   linkding, papra        │   │                          │
   │  Jellyfin, Sonarr,       │   │                          │
   │  Radarr, Prowlarr,       │   │                          │
   │  qBittorrent, Jellyseerr │   │                          │
   │  Immich (server + ML)    │   │                          │
   └──────────┬───────────────┘   └──────────┬───────────────┘
              │ NFS (10GbE)                  │ NFS
              ▼                              ▼
    ┌─────────────────┐            ┌─────────────────┐
    │ nas / NixOS     │            │ nas / NixOS     │
    │ 192.168.20.31   │            │ 192.168.20.31   │
    │ NFS: media,     │            │ NFS: backups    │
    │ photos, backups │            └─────────────────┘
    └─────────────────┘

Also on LAN: homeassistant / HAOS at 192.168.20.51, Nebula 10.10.0.51.
Laptop: think / custom Bluefin (Fedora atomic), tooling under `hosts/thinkpad/`.
```

## Machine Registry

| Host            | LAN IP            | Nebula IP                             | OS          | Config                               | Purpose / services                                                                                                                                                                                 |
| --------------- | ----------------- | ------------------------------------- | ----------- | ------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `bees`          | `192.168.20.41`   | `10.10.0.6`                           | NixOS 25.11 | `hosts/bees/`                        | Production server: Caddy (**internal `*.internal.crussell.io` only**), ntfy, datenight, linkding, papra, Jellyfin, Sonarr, Radarr, Prowlarr, qBittorrent, Jellyseerr, Immich. |
| `bee`           | `192.168.20.105`  | `10.10.0.12` + lighthouse `10.10.0.1` | NixOS 25.11 | `hosts/bee/`                         | Dev server: Nebula lighthouse (local LH `10.10.0.1` + Hetzner relay), self-hosted Buzz relay, Hermes Agent gateway, dsh web UI, dev quadlets (gpl/polymer/buildspace), restic backup.                                |
| `think`          | varies            | `10.10.0.10`                          | Bluefin (atomic) | `hosts/thinkpad/`               | Laptop: custom Bluefin image, bubblebox tools, Nebula client (container). Resolves Nebula overlay names via baked `/usr/etc/hosts` (Containerfile step 3.7). Not a NixOS deploy target. |
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

**Deploy origin is `bees`.** The thinkpad no longer runs NixOS (it's a custom
Bluefin / Fedora atomic image now), so all NixOS builds and deploys originate from `bees`
itself — the most powerful machine and always on. Builds happen on `bees`; the
resulting closure is pushed to the target over Nebula and switched. When the
target *is* `bees`, the deploy script does a direct local switch (no SSH-to-self).

Available NixOS hosts (deploy targets): `bee`, `bees`, `nas`, `gateway`.

Standard deploy (run from bees):

```bash
ssh -o IdentitiesOnly=yes crussell@10.10.0.6
cd ~/Code/cn && git pull
nix run .#deploy -- bees      # local switch on bees (no SSH-to-self)
nix run .#deploy -- bee       # build on bees, push closure to bee
nix run .#deploy -- bee bees  # multiple at once
nix run .#deploy -- gateway   # build on bees, push closure to gateway
```

Fallback if `bees` is down — pull the flake from GitHub and build on each target
(secrets still decrypt on-target via agenix, so no key material is needed beyond
what the target already holds):

```bash
ssh -o IdentitiesOnly=yes crussell@<host-nebula-ip>
sudo nixos-rebuild switch --flake github:chad-russell/cn#<host>
```

Install/wipe a new host with nixos-anywhere (requires mandatory safety flag):

```bash
# WARNING: destructive. The flag is mandatory to prevent confusing install with deploy.
nix run .#install -- bees 192.168.20.41 --i-understand-this-wipes-the-disk
nix run .#install -- bee 192.168.20.105 --i-understand-this-wipes-the-disk
```

Useful validation before deploy:

```bash
# Eval gate: check all hosts eval cleanly (fast — no building)
nix flake check

# Eval a single host
nix eval .#nixosConfigurations.bees.config.networking.hostName --raw

# Build without switching
nix build .#nixosConfigurations.bees.config.system.build.toplevel

# Format check (no changes if clean)
nix shell nixpkgs#treefmt nixpkgs#nixfmt-classic -c treefmt --ci
```

## Service Operations by Host

### bees — Production server (all workloads)

Source files:

- `hosts/bees/configuration.nix`
- `hosts/bees/caddy.nix` + `hosts/bees/caddy/` (Caddyfile, routes, caddy.container)
- `hosts/bees/media-services.nix` — Jellyfin, Sonarr, Radarr, Prowlarr, qBittorrent, Jellyseerr
- `hosts/bees/immich.nix` + `hosts/bees/immich-backup.nix` — Immich server + ML
- `hosts/bees/beszel.nix` — Beszel monitoring hub
- `hosts/bees/thinkpad-registry.nix` + `zot.container` — zot OCI registry (thinkpad host images) + daily build/publish service
- `hosts/bees/ntfy.nix`, `datenight.nix`
- `hosts/bees/services.nix` + `*.container` — linkding, papra
- `hosts/bees/backup.nix` — Restic backup to S3
- `*.container` files — jellyfin, jellyseerr, sonarr, radarr, prowlarr, qbittorrent, linkding, papra

Live systemd services:

- `nebula@homelab.service` — service identity `10.10.0.6`
- `caddy.service` — Podman Quadlet, container name `systemd-caddy`
- `ntfy-sh.service` — port `8090`
- `datenight.service` — port `7890`
- `linkding.service` — publishes `30080 -> 9090`
- `papra.service` — publishes `30083 -> 1221`
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
- `beszel.service` — Beszel monitoring hub, `127.0.0.1:8091` (8091 not its default 8090, which ntfy uses)

Storage:

- `/mnt/media` from `192.168.20.31:/pool/media`
- `/mnt/photos` from `192.168.20.31:/pool/photos`
- `/mnt/backups` automount from `192.168.20.31:/pool/backups`

Useful checks:

```bash
ssh -o IdentitiesOnly=yes crussell@192.168.20.41
systemctl status caddy ntfy-sh datenight linkding papra jellyfin sonarr radarr prowlarr jellyseerr qbittorrent immich-server
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

- `services.caddy` — linkding, papra, ntfy, hermes (webui on bee over Nebula)
- `media.caddy` — qBittorrent, Sonarr, Radarr, Prowlarr, Jellyseerr, Jellyfin internal
- `beszel.caddy` — Beszel hub (`beszel.internal.crussell.io` → `127.0.0.1:8091`, incl. WebSocket)

#### Updating Caddy Routes

Edit repo source files, deploy `bees` to update `/etc/caddy`, then **restart the
Caddy container** for changes to take effect. A bare `caddy reload` inside the
container is NOT enough: the Caddyfile and routes are NixOS `etc` symlinks, and
the podman container bind-mounts them at start — so a deploy repoints the
symlink on the host, but the running container keeps the old store path until
the container is recreated.

```bash
# from repo root
nix run .#deploy -- bees

ssh -o IdentitiesOnly=yes crussell@10.10.0.6 '
  sudo systemctl restart caddy.service &&
  sudo podman exec systemd-caddy caddy validate --config /etc/caddy/Caddyfile
'
```

The container is named `systemd-caddy` and managed by the `caddy.service` Quadlet.

Caddy's Route53 DNS challenge credentials are managed via agenix (`secrets/aws-env.age`), decrypted at runtime to `/run/agenix/aws-env`. **Bees uses this only for the internal `*.internal.crussell.io` wildcard cert**; the gateway's public ingress uses HTTP-01 and needs no credentials.

#### Beszel (resource monitoring)

[Beszel](https://beszel.dev) provides historical + current CPU/memory/disk/network stats across hosts, with a web dashboard and a PocketBase REST API. No Prometheus/Grafana — just a single Go hub binary + SQLite and tiny agent binaries, all from the one nixpkgs `beszel` package.

- **Hub:** native `beszel.service` on bees, `127.0.0.1:8091`, fronted by `beszel.internal.crussell.io` (Caddy route `hosts/bees/caddy/routes/internal/beszel.caddy`). Config: `hosts/bees/beszel.nix`. PocketBase data in `/var/lib/beszel`. REST API at `https://beszel.internal.crussell.io/api/...` (auth required).
- **Agents:** `modules/beszel-agent.nix` is imported by `bees`, `bee`, `nas`, `gateway`. Each agent connects OUT to the hub over the Nebula overlay via WebSocket (`DISABLE_SSH=true` — **no inbound port on any host**), authenticating with a universal token. Runs as its own `beszel-agent` user.
- **Secret:** `secrets/beszel-agent-env.age` holds `KEY=<hub public key>` + `TOKEN=<universal token>` (one env file shared by all agents), created in the hub UI under Settings → Tokens. Owned by `beszel-agent` so the non-root service can read it.
- The NAS agent additionally reports `/pool` (`extraFilesystems`).

```bash
ssh -o IdentitiesOnly=yes crussell@10.10.0.6
systemctl status beszel beszel-agent        # hub + local agent
journalctl -u beszel-agent | grep WebSocket # confirm connection
# agents on other hosts: ssh crussell@10.10.0.12 / .3 ; root@178.156.171.212
```

To rotate the token: create a new one in the hub UI, re-encrypt `secrets/beszel-agent-env.age` (see Secrets), and redeploy all hosts.

### bee — Dev server + Nebula lighthouse

Source files:

- `hosts/bee/configuration.nix` — host config + Hermes Agent gateway
- `hosts/bee/disk-config.nix`
- `hosts/bee/backup.nix` — Restic backup to S3
- `hosts/bee/tailscale.nix` — on-demand Tailscale (not enabled at boot)
- `hosts/bee/buzz-relay.nix` + `buzz-relay.pod` + `buzz-*.container` — self-hosted Buzz relay
- `hosts/bee/dev-quadlets.nix` + `dev-quadlets/` — dev environment stacks

Running services:

- `nebula@homelab.service` — `10.10.0.12`
- `nebula@lighthouse.service` — local lighthouse `10.10.0.1`, UDP `4243`
- `hermes-agent.service` — Hermes Agent gateway (replaces buzz-acp; see `hosts/bee/configuration.nix`). Runs as `crussell` with full host access. Connects to the Buzz relay via NIP-42 auth, uses the `buzz` CLI for outbound message delivery. Memory backend: **mem0 (OSS mode)** — mem0ai baked into the sealed venv via the package override in `hosts/bee/configuration.nix`; behavioral config (Z.AI extraction LLM + OpenRouter embeddings + local qdrant at `$HERMES_HOME/mem0_qdrant`) in `/var/lib/hermes/.hermes/mem0.json`.
- `hermes-serve.service` — Hermes JSON-RPC/WebSocket API on Nebula `10.10.0.12:9119` (desktop/mobile remote clients; basic-auth plugin). The WebUI (`hermes-webui.service`, port 8787, `https://hermes.internal.crussell.io`) was retired 2026-09-01 — desktop + Discord are the only chat surfaces.
- `buzz-relay-pod.service` — self-hosted Buzz relay (podman pod: relay, postgres, redis, minio, pair-relay)
- Dev stacks (`dev-quadlets/`) — gpl, polymer, buildspace (podman quadlets, reached via SSH tunnels; see `hosts/bee/dev-quadlets/README.md` and `cjust dev-tunnel`)
- Restic backup (daily S3 backup via `hosts/bee/backup.nix`)
- `dsh-web.service` — DeepSeek Harness web UI (`modules/dsh.nix`): loopback `:3080` → `dsh-web-proxy` socket on Nebula `10.10.0.12:3080` → bees Caddy `https://dsh.internal.crussell.io`. Default model `zai-coding/glm-5.3` (personal coding plan; replaces opencode, retired 2026-09-02). `codex` CLI also installed for work-lane delegation.
- Beszel agent (default-on via `modules/beszel-agent.nix`)

bee is podman-only (no Docker daemon). Deploy with `nix run .#deploy -- bee`
from the deploy origin (`bees`).

> Dev stacks for gpl, polymer, and buildspace run on bee via podman quadlets
> (`hosts/bee/dev-quadlets/`). They're reached from the thinkpad via SSH
> tunnels (`cjust dev-tunnel <project>`). The thinkpad also has local copies
> of the gpl/polymer quadlets under `hosts/thinkpad/gloo/` for when the laptop
> is offline.

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
nix run .#install -- gateway --i-understand-this-wipes-the-disk
```

Use `ssh -o IdentitiesOnly=yes root@178.156.171.212` to verify.

## Nebula VPN

Nix-managed server defaults live in:

- `modules/nebula-client.nix` — shared client defaults for all NixOS server hosts
- `modules/nebula-hosts.nix` — `/etc/hosts` entries for overlay names
- per-host overrides in `hosts/*/configuration.nix`

Current overlay host entries from `modules/nebula-hosts.nix`:

| Nebula IP    | Name / role                                 |
| ------------ | ------------------------------------------- |
| `10.10.0.1`  | `nebula-lh` — local lighthouse on `bee`     |
| `10.10.0.2`  | `nebula-hetzner` — Hetzner lighthouse/relay |
| `10.10.0.3`  | `nas`                                       |
| `10.10.0.6`  | `bees` — production server                  |
| `10.10.0.11` | `phone`                                     |
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

- `secrets/*.age` — server secrets (aws-env, openrouter-api-key, restic passwords, S3 credentials, beszel-agent-env).
- `nebula/pki/*.key.age` — Nebula private keys encrypted to the SSH ed25519 public key.

All secrets are encrypted to a single age public key (`crussell` in `secrets/secrets.nix`), so every host that consumes a secret must have the matching private identity at `/home/crussell/.config/age/key.txt` (set as `age.identityPaths` in `modules/base-server.nix`). `bees` and `bee` have always had it; **`nas` and `gateway` first needed a secret for the Beszel agent and so require the identity placed manually** (like Nebula certs) — copy it from `bees` after any `nixos-anywhere` reinstall:

```bash
ssh -o IdentitiesOnly=yes crussell@10.10.0.6 'cat ~/.config/age/key.txt' \
  | ssh -o IdentitiesOnly=yes <user>@<nas|gateway> \
    'mkdir -p ~/.config/age && cat > ~/.config/age/key.txt && chmod 600 ~/.config/age/key.txt'
```

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

Existing examples: `linkding.container`, `papra.container`, `caddy/caddy.container`.

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