# MinIO → RustFS migration plan

Status: **planning** (approved direction 2026-11-14: sidecar swaps now, shared
instance deferred to a trigger rule). Owner: Chad + Glen.

## Why

MinIO has been gutting its community edition since mid-2025 (web console and
management features removed from the OSS build, paywalled into AIStor) — see
[Blocks & Files](https://www.blocksandfiles.com/2025/06/19/minio-users-complain-after-admin-ui-removed-from-open-source-storage/)
and [Futuriom](https://www.futuriom.com/2025/06/23/minio-faces-fallout-for-stripping-functions-from-open-source-object-storage/).
[RustFS 1.0](https://github.com/rustfs/rustfs) is now GA: Rust, Apache-2.0,
S3-compatible, same 9000/9001 port convention, ships a
[NixOS module](https://docs.rustfs.com/) (`services.rustfs`) and a Docker Hub
image (`rustfs/rustfs`).

Honest caveat: RustFS GA is **weeks old**. Everything we run against it is
disposable dev data, which is exactly the right risk profile for adopting it
early. Nothing production-critical moves in this plan.

## Inventory (verified live 2026-11-14 + repo)

| Host | Stack | Unit / container | Image | Live state | Data | Scope |
| --- | --- | --- | --- | --- | --- | --- |
| bee | openbible (biblica/open-bible) | `openbible-dev-minio` | `minio/minio:latest` | **running 12d** | 236K | work → **draft PR** |
| bee | buildspace | `buildspace-dev-minio` | pinned `RELEASE.2025-02-18` | stopped | 108K | personal → normal PR |
| bee | storyhub | `storyhub-dev-minio` | `minio/minio:latest` | units only, not running | — | personal → normal PR |
| bee | bib677 / bib687 / qrcode-c3 | ad-hoc containers | minio + bitnamilegacy | exited / running | — | Gloo work → **out of scope now**; same recipe later via draft PR |
| think | buildspace (local copy) | `buildspace-dev-minio` | pinned `RELEASE.2025-02-18` | not running | — | personal → normal PR |
| bees | — | — | — | none (Lane's minio retired 2026-09-08) | — | — |
| nas | — | — | — | **none** (TrueNAS-era minio died with the Nix migration) | — | — |

Non-findings worth recording:

- **Production never touches MinIO.** Restic backups go to real AWS S3
  (`crussell-restic-backups`, us-east-2); papra uses filesystem storage; no
  production container has an S3 endpoint. This migration is dev-sidecars only.
- **The "NAS minio" was a memory of the TrueNAS era.** It predates the NixOS
  migration and no trace exists on the current NAS (checked processes, ports,
  podman, unit files, `/pool`, shell history).

## Topology decision rule (the shared-vs-sidecar distinction)

**Rule: data earns a shared instance when ANY of these become true —
otherwise it stays a per-project sidecar.**

1. **Survival** — the data must outlive stack teardown / `qd down` /
   project retirement (i.e. it's not throwaway dev state).
2. **Multiplicity** — more than one service, project, or machine consumes it.
3. **Operational weight** — it needs agenix creds, restic coverage, monitoring,
   or a TLS hostname (i.e. it's production-ish).

Conversely, a sidecar stays a sidecar when the stack must stay **hermetic**
(`qd up`/`down` self-contained, laptop-offline copy on think), creds are
throwaway, and losing the volume costs an afternoon at most.

Everything MinIO currently in scope fails all three tests → sidecar swap only.
The shared instance is **designed, deferred, and trigger-driven** (see below).

## Deferred design: shared RustFS on the NAS — **BUILT 2026-09-25**

The trigger fired: **central logging** (needs survival, is consumed by all
four hosts via OpenObserve on bees, and carries agenix creds + monitoring).
Built as `hosts/nas/rustfs.{nix,container}` — a podman quadlet rather than
the upstream `services.rustfs` NixOS module, per the 2026-09-25 decision to
standardize new services on podman/quadlet. Design notes for the record:

- Data under `/pool/rustfs` (btrfs RAID1 underneath), multi-directory pool
  `d0..d3` — SNSD unsupported and EC across directories adds bitrot
  protection on top of btrfs's disk redundancy. (as planned)
- Creds via agenix — one env file `rustfs-env.age` (RUSTFS_ACCESS_KEY +
  RUSTFS_SECRET_KEY together) rather than two separate files; bound to
  Nebula `10.10.0.3:9000` only via `PublishPort=10.10.0.3:9000:9000`.
- Restic coverage for `/pool/rustfs`: **still deferred** — nas has no
  restic job (it IS the backup target host); btrfs RAID1 is the current
  protection. Revisit if the store grows beyond logs.
- Per-service access keys: **still deferred** — OpenObserve uses the root
  pair (values mirrored in `openobserve-env.age` as `ZO_S3_*`; rotate both
  files together). Mint per-service keys when a second consumer appears.

Original candidate triggers (second restic target, artifact store, hindsight
attachments, immich cold tier) remain open for future consumers — point them
at `10.10.0.3:9000`, don't spawn new sidecars.

## The swap recipe (identical for every sidecar)

All four in-scope `.container` files have the same shape. Per stack:

```ini
# before (MinIO)
Image=docker.io/minio/minio:latest
Environment=MINIO_ROOT_USER=minio
Environment=MINIO_ROOT_PASSWORD=password
Volume=openbible-dev-minio.volume:/data
Exec=server /data --console-address :9001

# after (RustFS) — same creds, same ports, same alias
# (1.0.1 below does NOT exist on Docker Hub — verified via registry API
#  2026-09-25; 1.0.0 is the newest stable. Pin by digest like
#  hosts/nas/rustfs.container does.)
Image=docker.io/rustfs/rustfs:1.0.0
Environment=RUSTFS_ACCESS_KEY=minio
Environment=RUSTFS_SECRET_KEY=password
Environment=RUSTFS_VOLUMES=/data
Environment=RUSTFS_CONSOLE_ENABLE=true
Environment=RUSTFS_CONSOLE_ADDRESS=0.0.0.0:9001
Volume=openbible-dev-rustfs.volume:/data
# no Exec= — the rustfs image is self-contained
```

Mechanics and gotchas:

- **Keep credential values identical** (`minio`/`password`,
  `buildspace`/`buildspace123`) so app `.env` files and app-container env
  blocks are untouched. Only the variable *names* change.
- **Ports don't move**: API 9000 / console 9001 in-container; published ports
  (openbible 3402/3403, storyhub 3390/3391) unchanged. Presigned URLs embed the
  host only, so `S3_ENDPOINT` values stay valid. RustFS supports presigned
  GET/PUT, multipart, CORS, and bucket policies per its
  [S3 compatibility matrix](https://github.com/rustfs/rustfs/blob/main/docs/architecture/s3-compatibility-matrix.md)
  (the notable gap — POST-policy form uploads — nothing here uses).
- **UID 10001**: the rustfs image runs as `10001:10001`. In rootless quadlets
  add `PodmanArgs=--userns=keep-id:uid=10001,gid=10001` so the container user
  maps to crussell and the named volume stays writable. (Compose docs offer
  `--user <uid>:<gid>` as the alternative; keep-id is the podman-native fix.)
  **Validate this in the canary first** — it is the one piece with real
  uncertainty.
- **Fresh volume, new name** (`*-dev-rustfs.volume`): MinIO-written `xl.meta`
  is only preview-readable in RustFS (`rio-v2`, non-default), and all volumes
  hold ≤236K of disposable dev data. The old minio volume is left in place =
  instant rollback path.
- **Full rename, one commit per stack**: file renames ripple to the app
  container's `Requires=`/`After=`, `dev-quadlets.nix` lists, `qd` status
  lines, and README tables. Do the whole rename mechanically per stack so each
  stack is one revertible commit.
- **No dev-server.sh changes**: bucket bootstrap already uses the app's own
  AWS SDK `CreateBucket` — RustFS answers the same calls.
- Optional nicety once proven: quadlet healthcheck hitting `GET /health`.

## Execution order

1. **Canary — buildspace on bee** (personal, currently stopped, zero users).
   Branch → swap → PR → merge/deploy bee → `qd buildspace up` → verify bucket
   creation + app upload + `:9001` console → `qd buildspace down`. This proves
   the keep-id/UID-10001 mechanics before anything running is touched.
2. **storyhub on bee** (units exist, not running — same near-zero risk).
3. **openbible on bee** (**work project → draft PR only, Chad merges/deploys**;
   brief downtime when the 12-day-running stack recreates; note `MINIO_ROOT_*`
   → `RUSTFS_*` also applies to any `.env` docs in that repo if it pins them).
4. **thinkpad buildspace** — same file edit in `hosts/thinkpad/buildspace/`,
   applied on the laptop through its own quadlet install flow (not a NixOS
   deploy target).
5. **Gloo stacks (gpl, polymer, bib*, qrcode-c3)** — out of scope for now;
   recipe above applies verbatim when requested, delivered as **draft PRs**.
6. Cleanup (after everything green): delete retired `systemd-*-dev-minio`
   volumes; unpull `minio/minio` images on bee/think where no consumer remains.

Rollback at any step: revert the stack's commit, redeploy, `qd <proj> up` —
the old minio volume and image are still there.

## Risks / open items

- RustFS GA freshness (weeks) — mitigated by disposable-data scope + canary.
- `keep-id:uid=` mapping in rootless quadlets — canary proves it; fallback is
  `PodmanArgs=--user=1000:1000`.
- Console behavior differs from MinIO's (browser debugging on 3403/3391 may
  look different; acceptable).
- Unpinned `minio/minio:latest` references (openbible, storyhub) disappear
  with this migration anyway; the pinned-2025 buildspace images get retired
  too.
