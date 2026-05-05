# AGENTS.md

This is the root navigation and operating guide for this personal infrastructure repository.

## Repository Overview

Use this file for global context. For implementation details, open the subsystem docs directly.

### Core Infrastructure Docs

| Area                   | Doc                         | Purpose                                               |
| ---------------------- | --------------------------- | ----------------------------------------------------- |
| Nebula mesh VPN        | `nebula/README.md`          | Overlay topology, cert model, deploy/update workflows |
| Public ingress gateway | `servers/gateway/README.md` | Hetzner nginx SSL passthrough to hub over Nebula      |
| Hub migration history  | _(archived)_                | Swarm → Quadlets migration complete                   |

### Host and Service Docs

| Area                          | Doc                                           | Purpose                                                                                       |
| ----------------------------- | --------------------------------------------- | --------------------------------------------------------------------------------------------- |
| AI host (`bees`)              | `servers/ai/README.md`                        | llama.cpp + llama-swap operations                                                             |
| NAS                           | `servers/nas/README.md`                       | TrueNAS NFS exports                                                                           |
| Backup system                 | `servers/hub/backup/README.md`                | Restic backups to NAS with ntfy notifications                                                 |
| Desktop config tooling        | `brunch/README.md`, `brunch/config/README.md` | Brunch/Brioche tooling plus this repo's config layout                                         |
| Custom Fedora Atomic image    | `crussell-fin/AGENTS.md`                      | bootc image template for building personalized workstation images (based on finpilot/Bluefin) |
| Dev stacks (Gloo, Buildspace) | `brunch/config/agents/skills/gloo-hosting/SKILL.md`, `brunch/config/agents/skills/buildspace-hosting/SKILL.md` | Brunch-managed dev stack skills (infra + app services) |

### Config-First Directories (No README Yet)

- `servers/hub/quadlets/containers/` - Rootless Podman Quadlets for hub services
- `servers/hub/caddy/Caddyfile` - Caddy reverse proxy routes
- `servers/media/quadlets/` - Media stack containers on `media`

## Current Architecture

```text
                              Internet
                                  │
                    ┌─────────────▼─────────────┐
                    │      Hetzner VPS          │
                    │  178.156.171.212          │
                    │  (nginx: SSL passthrough) │
                    │  Nebula: 10.10.0.2        │
                    └─────────────┬─────────────┘
                                  │ Nebula VPN
┌─────────────────────────────────▼──────────────────────────────┐
│                              k2                                │
│              (192.168.20.62 - NixOS server)                    │
│                     Nebula split identity:                     │
│                     • 10.10.0.1 local lighthouse               │
│                     • 10.10.0.6 host/services endpoint         │
│                                                                │
│  Caddy reverse proxy (Podman container):                       │
│  • *.internal.crussell.io → internal services                  │
│  • *.crussell.io → public services (via Hetzner)               │
│                                                                │
│  Other services:                                               │
│  • Ntfy  • SearXNG  • Datenight                               │
│  • Papra  • Linkding                                           │
└─────────────────────────────────┬──────────────────────────────┘
                                  │
                    ┌─────────────┘
                    ▼
          ┌─────────────────┐
          │       bee       │
          │ 192.168.20.105  │
          │   NixOS 25.11   │
          │ Beelink mini PC │
          │  Nebula: 10.10.0.12  │
│          │  (fresh — services TBD)  │
│          └─────────────────┘
                                  │
                    ┌─────────────┴─────────────────────────────┐
                    ▼                                           ▼
          ┌─────────────────┐                       ┌─────────────────┐
          │       k3        │                       │       nas       │
          │ 192.168.20.63   │                       │ 192.168.20.31   │
          │   NixOS 25.11   │                       │   TrueNAS       │
          │ Media + Gloo    │                       │ NFS             │
          └─────────────────┘                       └─────────────────┘

           ┌─────────────────┐
           │  homeassistant  │
           │ 192.168.20.51   │
           │   HAOS          │
           └─────────────────┘
```

## Repository Structure

```text
.
├── AGENTS.md
├── brunch/
│   └── README.md
├── crussell-fin/
│   └── AGENTS.md
├── nebula/
│   ├── README.md
│   ├── configs/
│   ├── pki/
│   ├── quadlets/
│   └── scripts/
├── servers/
│   ├── ai/
│   │   └── README.md
│   ├── hub/
│   │   ├── backup/
│   │   │   └── README.md
│   │   ├── caddy/
│   │   │   ├── Caddyfile
│   │   │   └── routes/internal/   # Imported Caddy route snippets
│   │   ├── dev-stacks/
│   │   │   ├── gloo/
│   │   │   │   ├── compose.yaml
│   │   │   │   ├── Justfile
│   │   │   │   ├── host-envs/
│   │   │   │   ├── scripts/
│   │   │   │   └── secrets/
│   │   │   └── buildspace/compose.yaml
│   │   └── quadlets/
│   ├── homeassistant/
│   │   └── README.md
│   ├── media/
│   │   └── quadlets/
│   ├── nas/
│   │   └── README.md
│   └── gateway/
│       └── README.md
└── .archived/
    ├── nixos/
    └── swarm/
```

## Machine Registry

| Hostname      | IP Address      | OS            | Purpose            | Services                                                            |
| ------------- | --------------- | ------------- | ------------------ | ------------------------------------------------------------------- |
| bee           | 192.168.20.105  | NixOS 25.11   | General-purpose    | Beelink mini PC, Nebula client (10.10.0.12)                        |
| k1            | 192.168.20.61   | NixOS 25.11   | Utility server     | Bun, pi-coding-agent, Nebula client (10.10.0.4)                   |
| k2            | 192.168.20.62   | NixOS 25.11   | Utility server     | Caddy, Ntfy, SearXNG, Nebula lighthouse (10.10.0.1+10.10.0.6)     |
| k3            | 192.168.20.63   | NixOS 25.11   | Media server       | Jellyfin, Radarr, Sonarr, Prowlarr, qBittorrent, Jellyseerr, Nebula client |
| k4            | 192.168.20.64   | NixOS 25.11   | Utility server     | Immich, Nebula client                                             |
| nas           | 192.168.20.31   | TrueNAS       | Network storage    | NFS                                                                 |
| homeassistant | 192.168.20.51   | HAOS          | Smart home         | Home Assistant                                                      |
| gateway       | 178.156.171.212 | Fedora        | Public gateway/VPS | nginx (SSL passthrough → k2 via Nebula), Nebula lighthouse + relay  |
| think         | —               | NixOS 25.11   | Laptop             | ThinkPad T14                                                        |

## SSH Configuration

- **SSH key:** `~/.ssh/id_ed25519`
- **Username:** `crussell`
- **Always use:** `-o IdentitiesOnly=yes` when piping data to avoid agent issues

## Hub Operations (Quick Reference)

Services run as rootless Podman containers via systemd Quadlets.

For the brunch-managed dev stacks (`servers/hub/dev-stacks/`), do not manually install or symlink user units. The source of truth for those units is `brunch/config/hosts/hub/dev-stacks.bri`, applied with `brunch apply ./config --target hub`.

```bash
# View quadlet source files in repo
ls servers/hub/quadlets/containers/

# Install/update user quadlets from repo
cp servers/hub/quadlets/containers/*.container ~/.config/containers/systemd/
systemctl --user daemon-reload
systemctl --user restart <service>

# Check service status and logs
systemctl --user status <service>
journalctl --user -u <service>
```

Caddy config lives in `servers/hub/caddy/`. The Caddyfile imports route snippets from `routes/internal/*.caddy`. Both are mounted read-only into the container directly from the repo.

```bash
# Add a new internal route
# 1. Create servers/hub/caddy/routes/internal/<name>.caddy
# 2. Validate/reload:
sudo podman exec systemd-caddy caddy validate --config /etc/caddy/Caddyfile
sudo podman exec systemd-caddy caddy reload --config /etc/caddy/Caddyfile
```

### Secret Management

Secrets are encrypted with [age](https://github.com/FiloSottile/age) using the SSH ed25519 key (`~/.ssh/id_ed25519`). Decrypt from any machine with that key:

```bash
age -d -i ~/.ssh/id_ed25519 <file>.age
```

### Nebula PKI (`nebula/pki/`)

- **Certs (`*.crt`)** — committed plain (public, no secrets)
- **Private keys (`*.key.age`)** — encrypted with age, committed to git
- **Raw keys (`*.key`)** — gitignored, never committed
- **Phone config (`configs/phone.yaml.age`)** — encrypted (has embedded private key)
- **`secrets.nix`** — defines recipient keys for agenix workflows

The CA private key (`ca.key.age`) can sign arbitrary nebula certs — treat it as critical infrastructure.

### Application secrets (`servers/hub/quadlets/secrets/*.age`)

Encrypted with age, decrypted during setup by `setup-quadlets.sh`.

**Prerequisites:**

- Age key at `~/.config/age/key.txt`
- Age binary installed (`~/.local/bin/age` or system-wide)

See `servers/hub/quadlets/secrets/README.md` for:

- List of encrypted files and their contents
- Manual decryption commands
- Instructions for rotating secrets

## Adding or Updating a Hub Service

1. Add or edit a quadlet in `servers/hub/quadlets/containers/`.
2. If externally reachable, add/update route(s) in `servers/hub/caddy/Caddyfile`.
3. Deploy quadlet to `~/.config/containers/systemd/`, reload daemon, and restart service.
4. Verify with service logs and HTTP checks.

For Gloo / Buildspace app dev services, use the `gloo-hosting` or `buildspace-hosting` skills instead; those services are host-run dev servers managed by brunch user units, not by copying quadlets manually.

## Archived / Deprecated

Deprecated configs are retained under `.archived/`:

- `.archived/nixos/` - Legacy NixOS configs for decommissioned hosts
- `.archived/swarm/` - Legacy Docker Swarm stack files
- `.archived/brunch-modules/` - Legacy brunch modules for gloo/buildspace/dev-infra
