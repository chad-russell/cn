# crussell-srv

Server-focused Universal Blue image for homelab consolidation.

## What's Included

- **Base:** `ghcr.io/ublue-os/base-main` (Fedora, no desktop)
- **Container runtime:** Podman + podman-compose
- **Backup:** Restic
- **Networking:** Tailscale
- **Monitoring:** htop, btop, iotop, lm_sensors
- **Storage tools:** ncdu, dust, smartmontools, nvme-cli
- **Modern CLI:** ripgrep, fd, bat, eza, jq, yq
- **Shell:** Zsh with sensible defaults

## Building

```bash
# Build the image
just build

# Build and switch (on a bootc system)
just switch

# Build a QCOW2 for testing in a VM
just build-qcow2
```

## First Boot

1. Login as root or created user
2. Connect to Tailscale: `sudo tailscale up`
3. Configure firewall: `ujust configure-firewall`
4. Install additional tools: `ujust install-server-tools`

## Useful Commands (ujust)

```bash
ujust ps              # Show all containers
ujust logs <name>     # Follow container logs
ujust up [path]       # Start a compose stack
ujust down [path]     # Stop a compose stack
ujust prune           # Clean up unused containers/images
ujust disk-usage      # Show storage usage
ujust info            # Show system info
```

## Migrating from Swarm

Since this is a single-machine setup, use `podman-compose` instead of Docker Swarm:

1. Copy your compose files from `docker/swarm/` 
2. Remove Swarm-specific directives (`deploy:`, `replicas:`, etc.)
3. Run with `podman-compose up -d`

See the `compose/` directory for converted stack files.
