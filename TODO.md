# TODO List - Restic Backup Implementation

## High Priority

- [ ] Fix container name resolution in restic-backup.sh (use partial matching instead of exact match)
- [ ] Remove old backup system (container-backup.nix) from k2/k3/k4 configs
- [ ] Add all docker/swarm services to restic-backup.json configs

## Medium Priority

- [ ] Deploy restic system to k3
- [ ] Deploy restic system to k4
- [ ] Test backup and restore for each service
- [ ] Set up NTFY topic for restic failures

## Low Priority

- [ ] Migrate password management to sops-nix or agenix
- [ ] Add backup monitoring dashboard
- [ ] Add automated backup testing

## Completed

- [x] Create restic-backup.nix NixOS module
- [x] Create restic-backup.sh script
- [x] Create restic-restore.sh script
- [x] Initialize restic repository on k2
- [x] Deploy to k2 and verify Linkding backup works
- [x] Add documentation to AGENTS.md
- [x] Generate and store restic password (save to Bitwarden!)

## Services to Add (from docker/swarm/)

### k2 Services
- [x] karakeep (volumes: karakeep-app-data, karakeep-data, karakeep-homedash-config)
- [x] memos (volume: memos-data)
- [x] ntfy (volumes: ntfy-config, ntfy-cache)
- [x] adguardhome (volumes: dozzle_adguardhome-conf, dozzle_adguardhome-work)
- [x] caddy (bind: /home/crussell/caddy/Caddyfile)
- [x] immich-postgres (volume: immich-swarm_postgres_data)
- [x] searxng (volume: searxng_searxng-valkey-data)
- [ ] linkding (bind: /mnt/swarm-data/linkding)

### k3 Services
- [x] audiobookshelf (bind: /mnt/swarm-data/audiobookshelf)
- [ ] papra (volume: papra-data)
- [ ] n8n (volume: onyx_onyx-db-volume)
- [ ] openwebui (volume: need to check actual name)
- [ ] searxng (volume: searxng_searxng-valkey-data)

### k4 Services
- [ ] beszel (volume: need to check actual name)
- [ ] immich services (volumes: need to check actual names)
