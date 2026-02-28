# TODO List

## High Priority

- [ ] Test backup and restore for each service (crussell-srv)
- [ ] Set up NTFY topic for restic failures

## k1 Media Server

- [ ] Migrate to Fedora Atomic (Silverblue/Bluefin-style)
- [ ] Capture all service configs into this repo
- [ ] Create Quadlet definitions for Jellyfin, Radarr, Sonarr, Prowlarr, qBittorrent, Jellyseerr
- [ ] Document volume mounts and data locations
- [ ] Add to restic backup configuration

## Medium Priority

- [ ] Add backup monitoring dashboard
- [ ] Migrate password management to sops or similar

## Low Priority

- [ ] Add automated backup testing

## Completed

- [x] Archive NixOS configs (k2, k3, k4) - machines decommissioned
- [x] Archive Docker Swarm configs - migrated to Podman Quadlets
- [x] Consolidate archived files into archived/ folder
- [x] Update AGENTS.md to reflect simplified architecture
