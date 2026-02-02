# TODO List - Restic Backup Implementation

## High Priority

- [x] Fix container name resolution in restic-backup.sh (use partial matching instead of exact match)
- [x] Remove old backup system (container-backup.nix) from k2/k3/k4 configs
- [x] Add all docker/swarm services to restic-backup.json configs
- [ ] Deploy restic system to k3
- [ ] Deploy restic system to k4
- [ ] Test backup and restore for each service
- [ ] Set up NTFY topic for restic failures

## Medium Priority

- [ ] Test backup and restore for each service
- [ ] Migrate password management to sops-nix or agenix
- [ ] Add backup monitoring dashboard

## Low Priority

- [ ] Add automated backup testing

## Completed

- [x] Create restic-backup.nix NixOS module
- [x] Create restic-backup.sh script
- [x] Create restic-restore.sh script
- [x] Initialize restic repository on k2
- [x] Deploy to k2 and verify Linkding backup works
- [x] Add documentation to AGENTS.md
- [x] Generate and store restic password (save to Bitwarden!)
- [x] Remove old docker folders (k2/docker, k3/docker, k4/docker)
- [x] Create restic configs for k2, k3, k4
- [x] Add linkding to k2 config
- [x] Update k2 configuration to use restic-backup module
- [x] Commit restic backup changes on k2
