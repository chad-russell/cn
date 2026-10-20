# cn

Unified NixOS configurations for my homelab infrastructure — one flake, every
machine: home servers, the public ingress VPS, the NAS, and a Bluefin-based
laptop, all tied together by a Nebula overlay network.

**Source of truth:** `flake.nix`, `hosts/*/*.nix`, `modules/*.nix`, and live
host state. Prefer these over older docs when facts disagree. Agent-facing
operating guide: [AGENTS.md](AGENTS.md).

## Hosts

| Host | Hardware | Role |
| --- | --- | --- |
| `bee` | Beelink mini PC | Dev server + local Nebula lighthouse (dev quadlets, filebrowser, hindsight) |
| `bees` | Production server | Shared + media + internal services behind Caddy ingress (Immich, Jellyfin, *arr, linkding, papra, ntfy, …) |
| `gateway` | Hetzner Cloud VPS | Public TLS ingress (Caddy, HTTP-01), Nebula lighthouse/relay |
| `nas` | NFS storage server | NFS + Samba exports, shared RustFS S3 (10.10.0.3:9000), btrfs maintenance |
| `homeassistant` | HAOS appliance | Home Assistant OS + local Nebula add-on, incident notes |
| `think` | ThinkPad | Custom Bluefin (bootc) image — managed by its `Justfile`/`cjust`, not a NixOS deploy target |

Host addressing and deploy metadata live in [`lib/host-meta.nix`](lib/host-meta.nix)
— the single source of truth. Add a host there and the deploy scripts and
`/etc/hosts` overlay follow automatically.

## Layout

```text
flake.nix              # hosts, deploy/install apps, checks
hosts/                 # per-machine NixOS configs (see table above)
modules/               # shared NixOS modules (nebula, restic, vector, …)
lib/                   # host-meta.nix, nfs-mount helper
pkgs/                  # in-repo packages (dsh)
nebula/                # overlay network PKI, configs, scripts, reference
scripts/               # deploy.sh, ci-log.sh, verify-immich.sh
docs/                  # topic deep-dives (rustfs migration, immich loop, …)
secrets/               # agenix-encrypted secrets
.forgejo/workflows/    # CI: PR checks, merge → auto-deploy, flake updates
```

## Network

Nebula overlay `10.10.0.0/24` — full topology in
[`nebula/README.md`](nebula/README.md). At home, peers discover each other via
the local lighthouse on `bee`; away, via the Hetzner lighthouse/relay on
`gateway`. Public ingress routes through `gateway` to `bees` without exposing
the home WAN.

## Workflow

- **Origin is Forgejo** (`git.crussell.io/chad/cn`). GitHub `chad-russell/cn`
  is an automatic push mirror — never push to GitHub directly.
- PRs run `ci.yml` (nix flake check + treefmt); merging to `main` triggers
  `deploy.yml` to auto-deploy.
- Deploy by hand with `nix run .#deploy -- <host>` **from `bees`** (the deploy
  origin).
- Formatting: `treefmt` (nixfmt-classic).
- Secrets: agenix — never commit plaintext.
