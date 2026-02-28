# k1 - Media Server

**IP:** 192.168.20.61
**OS:** Fedora Server (to be migrated to Fedora Atomic)
**Container Runtime:** Podman (rootless)

## Current Services

| Service | Purpose | Port |
|---------|---------|------|
| Jellyfin | Media streaming | 8096 |
| Jellyseerr | Request management | 5055 |
| Radarr | Movie automation | 7878 |
| Sonarr | TV show automation | 8989 |
| Prowlarr | Indexer aggregation | 9696 |
| qBittorrent | Download client | 8080 |

## TODO

- [ ] Migrate to Fedora Atomic (Silverblue/Bluefin-style image-based system)
- [ ] Capture all service configurations into this repo
- [ ] Create Quadlet definitions for all services
- [ ] Document volume mounts and data locations
- [ ] Add to restic backup configuration

## SSH Access

```bash
ssh -i ~/.ssh/id_ed25519 crussell@192.168.20.61
```

## Notes

This machine is currently running Fedora Server Edition. Long-term goal is to migrate to a Fedora Atomic (image-based) distribution for better consistency with the rest of the infrastructure.
