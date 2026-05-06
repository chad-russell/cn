# AGENTS.md

Root navigation and operating guide for agents working in this personal infrastructure repository.

**Read this first.** The repository is mid-migration from older `servers/` / `brunch/` layouts to a unified Nix flake. Prefer the Nix configuration and live hosts over older docs when facts disagree.

Last spot-checked via SSH: **2026-05-05**.

## Ground Rules for Agents

1. **Source of truth:** `flake.nix`, `hosts/*/*.nix`, `modules/*.nix`, and live host state are authoritative.
2. **Do not resurrect legacy paths** such as `servers/hub/...`, `servers/media/...`, or `brunch/...` unless the user explicitly asks. Those paths are deleted or deprecated in the current working tree.
3. **Use Nix for host config changes** whenever possible. Deploy with `nix run .#deploy -- <host>`.
4. **Caddy route source lives in `hosts/k2/caddy/`** and is installed to `/etc/caddy` by the `hosts/k2/caddy.nix` module; deploy `k2`, then validate/reload Caddy.
5. **Never commit plaintext secrets.** Existing plaintext secret-like files should be treated carefully; do not print or copy their contents into docs, logs, or chat unless explicitly necessary.
6. **When unsure, verify live state over SSH** using the SSH notes below.

## Current Repository Map

```text
.
├── flake.nix                  # Unified NixOS flake: hosts, deploy/install apps
├── flake.lock
├── AGENTS.md                  # This guide
├── hosts/
│   ├── bee/configuration.nix  # Beelink mini PC, general-purpose server
│   ├── homeassistant/         # HAOS operational docs + helper scripts
│   ├── k1/                    # Dev host: Gloo enabled, Buildspace optional
│   ├── k2/                    # Ingress/service host: Caddy, ntfy, searxng, datenight, linkding, papra, open-webui
│   ├── k3/                    # Media server: Jellyfin/*arr/qBittorrent/Jellyseerr
│   └── k4/                    # Immich photo server
├── modules/
│   ├── base-server.nix        # Shared server baseline: user, SSH, networkd, packages, GC, NFS client
│   ├── server-shell.nix       # Shared zsh/CLI setup for servers
│   ├── nebula-client.nix      # Shared Nebula client defaults for servers
│   ├── nebula-hosts.nix       # /etc/hosts entries for Nebula overlay names
│   ├── elitedesk-*.nix        # HP EliteDesk hardware, disk layout, NIC quirks
│   └── hub-disk-config.nix    # Beelink/bee btrfs disk layout
├── nebula/
│   ├── configs/               # Nebula config templates; some comments may be stale
│   ├── pki/                   # Nebula CA/certs and age-encrypted private keys
│   ├── quadlets/              # Legacy/manual Nebula Quadlets
│   └── scripts/               # Nebula helper binaries/scripts
├── secrets/                   # Agenix secrets used by server modules, e.g. Gloo
└── thinkpad/                  # `think` laptop NixOS + home-manager config
```

## Current Architecture

```text
                                Internet
                                    │
                                    ▼
                  ┌──────────────────────────────────┐
                  │ gateway / Hetzner VPS            │
                  │ 178.156.171.212 / Fedora 42      │
                  │ nginx stream passthrough :80/:443│
                  │ Nebula lighthouse+relay 10.10.0.2│
                  └────────────────┬─────────────────┘
                                   │ Nebula to 10.10.0.6
                                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│ k2 — ingress + shared services                                      │
│ 192.168.20.62 / NixOS 25.11                                        │
│ Nebula service identity: 10.10.0.6                                  │
│ Nebula local lighthouse: 10.10.0.1 on UDP 4243                      │
│ Caddy terminates TLS and routes public/internal domains             │
│ Native services: ntfy, SearXNG, datenight                           │
│ Podman Quadlets: linkding, papra, open-webui, caddy                 │
└───────────────────────────┬─────────────────────────────────────────┘
                            │ LAN / Nebula
        ┌───────────────────┼────────────────────┬────────────────────┐
        ▼                   ▼                    ▼                    ▼
┌──────────────┐    ┌──────────────┐     ┌──────────────┐    ┌──────────────┐
│ k1           │    │ k3           │     │ k4           │    │ bee          │
│ 192.168.20.61│    │ 192.168.20.63│     │ 192.168.20.64│    │ 192.168.20.105│
│ Nebula .4    │    │ Nebula .8    │     │ Nebula .9    │    │ Nebula .12   │
│ Dev stacks   │    │ Media stack  │     │ Immich       │    │ General use  │
└──────────────┘    └──────────────┘     └──────────────┘    └──────────────┘
        │                   │                    │
        └───────────────────┴──────────┬─────────┘
                                       ▼
                              ┌─────────────────┐
                              │ nas / TrueNAS   │
                              │ 192.168.20.31   │
                              │ NFS exports     │
                              └─────────────────┘

Also on LAN: homeassistant / HAOS at 192.168.20.51.
Laptop: think / NixOS 25.11, configured under `thinkpad/`.
```

## Machine Registry

| Host | LAN / Public IP | Nebula IP | OS | Config | Purpose / services |
| --- | --- | --- | --- | --- | --- |
| `k1` | `192.168.20.61` | `10.10.0.4` | NixOS 25.11 | `hosts/k1/` | Dev host. Gloo enabled; Buildspace module present but disabled. Bun/Node/pi-coding-agent. |
| `k2` | `192.168.20.62` | `10.10.0.6` + lighthouse `10.10.0.1` | NixOS 25.11 | `hosts/k2/` | Main ingress and shared services: Caddy, ntfy, SearXNG, datenight, linkding, papra, open-webui. |
| `k3` | `192.168.20.63` | `10.10.0.8` | NixOS 25.11 | `hosts/k3/` | Media server: Jellyfin, Sonarr, Radarr, Prowlarr, qBittorrent, Jellyseerr. |
| `k4` | `192.168.20.64` | `10.10.0.9` | NixOS 25.11 | `hosts/k4/` | Immich photo server; `/mnt/photos` from NAS. |
| `bee` | `192.168.20.105` | `10.10.0.12` | NixOS 25.11 | `hosts/bee/` | Beelink mini PC, general-purpose server; no major app services configured. |
| `think` | varies | `10.10.0.10` | NixOS 25.11 | `thinkpad/` | Laptop with home-manager, niri, Noctalia, Podman, dev tools. |
| `nas` | `192.168.20.31` | `10.10.0.3` | TrueNAS | not Nix-managed here | NFS storage: media, photos, backups. |
| `homeassistant` | `192.168.20.51` | — | HAOS | `hosts/homeassistant/` docs only | Home Assistant OS. |
| `gateway` | `178.156.171.212` | `10.10.0.2` | Fedora 42 | not Nix-managed here | Hetzner nginx stream proxy plus Nebula lighthouse/relay. |
| `bees` | — | `10.10.0.5` | not current Nix host | Nebula PKI only | Legacy/AI host identity remains in Nebula PKI. |

## SSH Access

Use the ed25519 key and force identities when automating:

```bash
ssh -o IdentitiesOnly=yes <user>@<host>
```

Common targets:

```bash
# NixOS servers installed for root SSH
ssh -o IdentitiesOnly=yes root@192.168.20.61   # k1
ssh -o IdentitiesOnly=yes root@192.168.20.62   # k2
ssh -o IdentitiesOnly=yes root@192.168.20.63   # k3
ssh -o IdentitiesOnly=yes root@192.168.20.64   # k4

# bee is deployed as crussell with sudo
ssh -o IdentitiesOnly=yes crussell@192.168.20.105

# Hetzner gateway
ssh -o IdentitiesOnly=yes root@178.156.171.212
```

Home Assistant SSH is different: see `hosts/homeassistant/README.md` and helper scripts under `hosts/homeassistant/scripts/`.

## Nix Operations

Available flake hosts:

```bash
nix flake show
# NixOS configs: think, k1, k2, k3, k4, bee
```

Deploy existing machines:

```bash
# One or more remote servers
nix run .#deploy -- k2
nix run .#deploy -- k1 k2 k4 bee

# Laptop, local rebuild
nix run .#deploy -- think
```

Install/wipe a new host with nixos-anywhere:

```bash
# WARNING: destructive
nix run .#install -- k1 192.168.20.61
nix run .#install -- bee 192.168.20.105
```

Useful validation before deploy:

```bash
# Fast eval check for a host
nix eval .#nixosConfigurations.k2.config.networking.hostName --raw

# Build without switching
nix build .#nixosConfigurations.k2.config.system.build.toplevel
```

### Known Nix Drift / Footguns

- Some historical comments may still say “hub” for services now running on `k2`. Prefer `hosts/k2/configuration.nix` and live `k2` state.
- `hosts/k2/caddy/aws.env` is still a plaintext Route53 credential file in the working tree. Treat it as sensitive; prefer moving it to agenix in a dedicated follow-up.

## Service Operations by Host

### k1 — Dev stacks

Source files:

- `hosts/k1/configuration.nix`
- `hosts/k1/gloo.nix`
- `hosts/k1/buildspace.nix`
- `hosts/k1/gloo/compose.yaml` and `hosts/k1/gloo/envs/*.env`
- `hosts/k1/buildspace/compose.yaml`
- `secrets/gloo-secrets.env.age`

Current Nix setting:

```nix
services.gloo.enable = true;
# services.buildspace.enable = true;
```

Gloo and Buildspace are intended to be mutually exclusive work contexts. User units are generated into `/home/crussell/.config/systemd/user/`, and linger is enabled.

Operate user services over SSH as root:

```bash
ssh -o IdentitiesOnly=yes root@192.168.20.61
export XDG_RUNTIME_DIR=/run/user/$(id -u crussell)
sudo -u crussell XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR systemctl --user status gloo-all.target
sudo -u crussell XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR systemctl --user start gloo-all.target
sudo -u crussell XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR journalctl --user -u gloo-polymer -f
```

Gloo ports/routes configured in Caddy:

| Service | Port | Internal hostname |
| --- | ---: | --- |
| GPL | 3106 | `gpl.internal.crussell.io` |
| Hummingbird API | 8000 | `hb-api.internal.crussell.io` |
| Hummingbird Web | 3100 | `hb-web.internal.crussell.io` |
| Polymer | 3001 | `polymer.internal.crussell.io` |
| RustFS API | 9000 | `rustfs.internal.crussell.io` |
| RustFS console | 9001 | `rustfs-console.internal.crussell.io` |
| pgAdmin | 5050 | `pgadmin.internal.crussell.io` |
| Storyhub | 3007 | `storyhub.internal.crussell.io` |

Buildspace routes are present in `hosts/k2/caddy/routes/internal/buildspace.caddy` and point to `k1` ports `3000`, `3002`-`3006`, and `3010`.

### k2 — Ingress and shared services

Source files:

- `hosts/k2/configuration.nix`
- `hosts/k2/caddy.nix`
- `hosts/k2/caddy/Caddyfile`
- `hosts/k2/caddy/routes/internal/*.caddy`
- `hosts/k2/ntfy.nix`, `searxng.nix`, `datenight.nix`
- `hosts/k2/hub-services.nix`
- `hosts/k2/*.container` for Linkding, Papra, Open WebUI

Live systemd services verified active:

- `nebula@homelab.service` — service identity `10.10.0.6`
- `nebula@lighthouse.service` — local lighthouse `10.10.0.1`, UDP `4243`
- `caddy.service` — Podman Quadlet, container name `systemd-caddy`
- `ntfy-sh.service` — port `8090`
- `searx.service` + `redis-searx.service` — SearXNG on port `8080`
- `datenight.service` — port `7890`
- `linkding.service` — publishes `30080 -> 9090`
- `papra.service` — publishes `30083 -> 1221`
- `open-webui.service` — publishes `30088 -> 8080`

Useful checks:

```bash
ssh -o IdentitiesOnly=yes root@192.168.20.62
systemctl status caddy ntfy-sh searx datenight linkding papra open-webui
podman ps
journalctl -u caddy -f
```

Caddy public routes in `hosts/k2/caddy/Caddyfile`:

| Public hostname | Backend |
| --- | --- |
| `homeassistant.crussell.io` | `192.168.20.51:8123` |
| `jellyfin.crussell.io` | `192.168.20.63:8096` |
| `photos.crussell.io` | `192.168.20.64:2283` |
| `datenight.crussell.io` | `192.168.20.62:7890` |

Internal route snippets live under `hosts/k2/caddy/routes/internal/`:

- `hub-services.caddy` — linkding, papra, ntfy, SearXNG, open-webui
- `media.caddy` — qBittorrent, Sonarr, Radarr, Prowlarr, Jellyseerr, Jellyfin internal
- `gloo.caddy` — Gloo dev stack on `k1`
- `buildspace.caddy` — Buildspace dev stack on `k1`
- `opencode.caddy` — retired placeholder

#### Updating Caddy Routes

Edit repo source files, deploy `k2` to update `/etc/caddy`, then validate and reload:

```bash
# from repo root
nix run .#deploy -- k2

ssh -o IdentitiesOnly=yes root@192.168.20.62 '
  podman exec systemd-caddy caddy validate --config /etc/caddy/Caddyfile &&
  podman exec systemd-caddy caddy reload --config /etc/caddy/Caddyfile
'
```

`hosts/k2/caddy/aws.env` / `/etc/caddy/aws.env` contains Route53 credentials for DNS-01 certificates. Treat it as sensitive and do not expose its contents.

### k3 — Media server

Source files:

- `hosts/k3/configuration.nix`
- `hosts/k3/media-services.nix`

Live services verified active:

- `jellyfin.service` — `8096`
- `sonarr.service` — `8989`
- `radarr.service` — `7878`
- `prowlarr.service` — `9696`
- `jellyseerr.service` — `5055`
- `qbittorrent.service` — Web UI `8080`, torrenting `51413`
- `nebula@homelab.service` — `10.10.0.8`

Storage:

- `/mnt/media` from `192.168.20.31:/mnt/tank/media`
- `/mnt/backups` automount from `192.168.20.31:/mnt/tank/backups`
- `/mnt/data` local ext4 disk by UUID
- Shared `media` group has GID `2000`

Common checks:

```bash
ssh -o IdentitiesOnly=yes root@192.168.20.63
systemctl status jellyfin sonarr radarr prowlarr jellyseerr qbittorrent
findmnt /mnt/media /mnt/backups /mnt/data
journalctl -u qbittorrent -f
```

### k4 — Immich

Source file: `hosts/k4/configuration.nix`.

Live services verified active:

- `immich-server.service` — port `2283`
- `immich-machine-learning.service`
- `redis-immich.service`
- `nebula@homelab.service` — `10.10.0.9`

Storage and permissions:

- `/mnt/photos` from `192.168.20.31:/mnt/tank/photos`
- Immich `mediaLocation = /mnt/photos`
- `nas-photos` group GID `1000` is added to Immich service supplementary groups.

Checks:

```bash
ssh -o IdentitiesOnly=yes root@192.168.20.64
systemctl status immich-server immich-machine-learning redis-immich
findmnt /mnt/photos
journalctl -u immich-server -f
```

### bee — Beelink mini PC

Source file: `hosts/bee/configuration.nix`.

- LAN `192.168.20.105`
- Nebula `10.10.0.12`
- NixOS 25.11
- Btrfs layout from `modules/hub-disk-config.nix`
- Nebula client enabled
- `/mnt/backups` NAS automount configured
- No major app services currently configured

Deploy uses `crussell@192.168.20.105 --sudo` per `flake.nix`.

### gateway — Hetzner VPS

Not Nix-managed by this flake. Verified live state:

- Fedora 42 host named `reverse-proxy`
- Public IP `178.156.171.212`
- Nebula `10.10.0.2`
- `nebula.service` active, UDP `4242`
- `nginx.service` active, TCP `80`/`443`
- `/etc/nginx/nginx.conf` stream-proxies:
  - HTTP `:80` -> `10.10.0.6:80`
  - HTTPS `:443` -> `10.10.0.6:443`

Use `ssh -o IdentitiesOnly=yes root@178.156.171.212` to verify.

## Nebula VPN

Nix-managed server defaults live in:

- `modules/nebula-client.nix`
- `modules/nebula-hosts.nix`
- per-host overrides in `hosts/*/configuration.nix`

Current overlay host entries from `modules/nebula-hosts.nix`:

| Nebula IP | Name / role |
| --- | --- |
| `10.10.0.1` | `nebula-lh` — local lighthouse on `k2` |
| `10.10.0.2` | `nebula-hetzner` — Hetzner lighthouse/relay |
| `10.10.0.3` | `nas` |
| `10.10.0.4` | `k1` |
| `10.10.0.5` | `bees` legacy/AI identity |
| `10.10.0.6` | `k2` service endpoint (Caddy/public ingress) |
| `10.10.0.7` | `k2` host identity cert exists in PKI but unused; `k2` maps to `10.10.0.6` |
| `10.10.0.8` | `k3` |
| `10.10.0.9` | `k4` |
| `10.10.0.10` | `think` |
| `10.10.0.12` | `bee` |

For NixOS hosts, certs are expected at:

```text
/etc/nebula/ca.crt
/etc/nebula/host.crt
/etc/nebula/host.key
```

`k2` also has local lighthouse certs at:

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
age -d -i ~/.ssh/id_ed25519 nebula/pki/k1.key.age > /tmp/k1.key
```

## Secrets

Agenix and age are both used:

- `secrets/gloo-secrets.env.age` — consumed by `hosts/k1/gloo.nix`; decrypted via `/home/crussell/.config/age/key.txt` on `k1`.
- `thinkpad/secrets/*.age` — home-manager/laptop secrets.
- `nebula/pki/*.key.age` — Nebula private keys encrypted to the SSH ed25519 public key.

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
5. Verify with `systemctl status`, `journalctl`, and HTTP checks.

### System Podman Quadlet on k2

Existing examples: `linkding.container`, `papra.container`, `open-webui.container`, `caddy/caddy.container`.

1. Add a `.container` file under `hosts/k2/` or `hosts/k2/caddy/`.
2. Add an `environment.etc."containers/systemd/<name>.container"` entry in a Nix module.
3. Ensure data directories/volumes in activation scripts if needed.
4. Deploy `k2` and start/restart `<name>.service`.
5. Add Caddy route if externally reachable.

### Caddy route change

1. Edit `hosts/k2/caddy/Caddyfile` for public routes or `hosts/k2/caddy/routes/internal/*.caddy` for internal routes.
2. Deploy `k2` so Nix updates `/etc/caddy`.
3. Validate and reload Caddy inside the `systemd-caddy` container.
4. Test with `curl -I https://<host>` from a network that can resolve/reach the domain.

## Archived / Deprecated Context

Older docs may refer to:

- `servers/hub/quadlets/...`
- `servers/hub/caddy/...`
- `servers/hub/dev-stacks/...`
- `servers/media/...`
- `brunch/config/...`
- host name `hub` for what is now mostly `k2`

Treat those as historical unless the files still exist and the current Nix config agrees. The current repo root shows many of those paths deleted in git status; do not base new work on them.
