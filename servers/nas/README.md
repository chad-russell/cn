# NAS (TrueNAS)

TrueNAS server at `192.168.20.31`.

## Services

| Service | Purpose |
|---------|---------|
| NFS | Network file sharing (`tank/backups`, `tank/photos`) |
| Docker | TrueNAS app platform |

## NFS Exports

| Path | Allowed Client | Purpose |
|------|---------------|---------|
| `tank/backups` | 192.168.20.105 (hub) | Restic backup target |
| `tank/photos` | 192.168.20.105 (hub) | Immich photo library mount |
