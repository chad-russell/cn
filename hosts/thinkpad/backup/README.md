# backup/ — restic offsite backup for think

S3-only restic backup of `/var/home/crussell`, run as a rootful Podman Quadlet
(mirroring `../nebula/`). Daily backup + forget/prune; weekly 5% integrity
check. Failures notify the `homelab-backups` ntfy topic.

**S3-only by design.** The laptop roams, and NFS-to-NAS is fragile off the home
network. S3 works over any internet connection and matches the policy that
everything important lives offsite. The NAS hosts (bees/bee) keep the local-copy
tier; think does not. `~/Code`, `~/.config`, `~/.ssh`, the Gloo stack, etc. ship
to S3; caches, build artifacts, container storage, flatpak app data (`.var`),
and VM images are excluded via `excludes`.

## Files

```text
backup/
├── image/                        # tiny restic image (clears entrypoint for shell chaining)
│   ├── Containerfile
│   └── build.sh
├── restic-backup.container       # daily backup Quadlet (S3)
├── restic-backup.timer
├── restic-check.container        # weekly check Quadlet (--read-data-subset=5%)
├── restic-check.timer
├── restic-ntfy-failure@.service  # host-curl ntfy notifier (OnFailure from above)
├── excludes                      # what NOT to back up (the lever for S3 data volume)
├── seed.sh                       # decrypt creds from repo -> /etc/restic-backup
├── install.sh                    # install units + enable timers
└── setup.sh                      # build + seed + init + install (the entry point)
```

## One-time prerequisite: the age identity

The repo's `secrets/*.age` are encrypted to the fleet age public key, so think
needs the matching private key (same one-time copy documented in the repo-wide
`AGENTS.md` for `nas`/`gateway`):

```bash
ssh -o IdentitiesOnly=yes crussell@10.10.0.6 \
  'cat ~/.config/age/key.txt' | sudo tee ~/.config/age/key.txt >/dev/null
sudo chmod 600 ~/.config/age/key.txt
```

This is the age key, **not** the SSH ed25519 key. (Nebula PKI is the exception:
those `.key.age` are encrypted to the SSH key, which is why `../nebula/seed.sh`
uses `~/.ssh/id_ed25519` instead.)

## Install / update

```bash
cjust backup        # or: hosts/thinkpad/backup/setup.sh
```

`setup.sh` is idempotent: builds the image, (re)seeds creds, ensures the S3 repo
exists, and (re)installs the timers. Run it after editing `excludes` or after
pulling changes to this directory.

## Manual operations

`restic.sh` is a thin wrapper that runs restic in the same image/env as the
backup containers (calls sudo internally):

```bash
# run a backup right now
sudo systemctl start restic-backup.service
sudo journalctl -u restic-backup.service -f

# check the timers
sudo systemctl list-timers 'restic-*'

# ad-hoc repo ops
hosts/thinkpad/backup/restic.sh snapshots
hosts/thinkpad/backup/restic.sh ls latest
hosts/thinkpad/backup/restic.sh stats --mode raw-data
hosts/thinkpad/backup/restic.sh forget <snapshot-id> --prune   # reclaim space
```

`restore` writes to the host, so bind an output dir yourself:

```bash
sudo podman run --rm -it \
  -v /etc/restic-backup:/secrets:ro \
  -v restic-backup-cache:/root/.cache/restic \
  -v /var/home/crussell/restore:/restore \
  --env-file /etc/restic-backup/s3.env \
  -e RESTIC_REPOSITORY=s3:https://s3.us-east-2.amazonaws.com/crussell-restic-backups/think \
  -e RESTIC_PASSWORD_FILE=/secrets/password \
  localhost/restic-backup:think \
  restic restore --target /restore latest
```

## Notes

- `RESTIC_REPOSITORY` is hardcoded in the two `.container` files and in
  `setup.sh`. It matches `modules/restic-backup.nix` (`crussell-restic-backups`,
  `us-east-2`, prefix `<hostname>`). Change all three together if it moves.
- Retention: `--keep-daily 30 --keep-monthly 12` (same as the S3 tier on
  bees/bee).
- The restic cache lives in a named root volume `restic-backup-cache`; deleting
  it just slows the next run (restic rebuilds it).
