#!/usr/bin/env bash
# One-time migration from the ad-hoc qrcode-c3 containers into the named
# volumes consumed by the qrcode-dev Quadlets.
#
# Data-format boundaries are respected:
#   PostgreSQL: pg_dump/pg_restore (never copy PGDATA while live)
#   S3:         mc mirror through the S3 API (never reuse MinIO disk layout)
#
# The old anonymous volumes and stopped containers are retained for rollback.
set -euo pipefail

OLD_APP="${OLD_APP:-qrcode-c3-app}"
OLD_DB="${OLD_DB:-qrcode-c3-pg}"
OLD_S3="${OLD_S3:-qrcode-c3-minio}"
NEW_DB_VOLUME="${NEW_DB_VOLUME:-systemd-qrcode-dev-db}"
NEW_S3_VOLUME="${NEW_S3_VOLUME:-systemd-qrcode-dev-rustfs}"
MIGRATE_DB="${MIGRATE_DB:-qrcode-migrate-db}"
MIGRATE_S3="${MIGRATE_S3:-qrcode-migrate-rustfs}"
RUSTFS_PORT="${RUSTFS_PORT:-9026}"
VERIFY_ONLY="${VERIFY_ONLY:-0}"
QUIESCE_SOURCE="${QUIESCE_SOURCE:-1}"
RUSTFS_IMAGE='docker.io/rustfs/rustfs@sha256:ba0a1b53e36f321c0d46f3867104abef169f7bc59c467c664ddac87e7ddc9a8b'
work="$(mktemp -d)"
success=0
app_was_running=0

cleanup() {
  podman rm -f "$MIGRATE_DB" "$MIGRATE_S3" >/dev/null 2>&1 || true
  rm -rf "$work"
  if [ "$success" -ne 1 ] && [ "$app_was_running" -eq 1 ]; then
    echo "==> migration failed — restarting old DB/S3/app"
    podman start "$OLD_DB" "$OLD_S3" >/dev/null 2>&1 || true
    podman start "$OLD_APP" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

for c in "$OLD_DB" "$OLD_S3"; do
  podman container exists "$c" || { echo "FATAL: source container $c not found" >&2; exit 1; }
done

# Target volumes must be fresh. Refuse to clobber a prior migration attempt.
for v in "$NEW_DB_VOLUME" "$NEW_S3_VOLUME"; do
  if podman volume exists "$v"; then
    count="$(find "$(podman volume inspect "$v" --format '{{.Mountpoint}}')" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)"
    [ "$count" -eq 0 ] || { echo "FATAL: target volume $v already contains data" >&2; exit 1; }
  else
    podman volume create "$v" >/dev/null
  fi
done

if podman container exists "$OLD_APP" && [ "$(podman inspect "$OLD_APP" --format '{{.State.Running}}')" = true ]; then
  app_was_running=1
  if [ "$QUIESCE_SOURCE" = 1 ]; then
    echo "==> stopping old app to quiesce DB/S3 writes"
    podman stop -t 20 "$OLD_APP" >/dev/null
  else
    echo "==> VERIFY ONLY: source app remains running; final cutover will quiesce writes"
  fi
fi

# ---------------------------------------------------------------------------
# PostgreSQL logical migration
# ---------------------------------------------------------------------------
echo "==> dumping PostgreSQL"
podman exec "$OLD_DB" pg_dump -U payload -d payload -Fc > "$work/payload.dump"
[ -s "$work/payload.dump" ] || { echo "FATAL: empty pg_dump" >&2; exit 1; }

podman rm -f "$MIGRATE_DB" >/dev/null 2>&1 || true
podman run -d --name "$MIGRATE_DB" \
  -e POSTGRES_PASSWORD=payload -e POSTGRES_USER=payload -e POSTGRES_DB=payload \
  -v "$NEW_DB_VOLUME:/var/lib/postgresql/data" \
  docker.io/library/postgres:17 >/dev/null
for _ in $(seq 1 60); do
  podman exec "$MIGRATE_DB" pg_isready -U payload -d payload >/dev/null 2>&1 && break
  sleep 1
done
podman exec "$MIGRATE_DB" pg_isready -U payload -d payload >/dev/null
cat "$work/payload.dump" | podman exec -i "$MIGRATE_DB" pg_restore -U payload -d payload --clean --if-exists --no-owner

# Compare row counts for every public base table. This catches silent partial
# restores while remaining schema-agnostic as Payload adds tables.
counts_sql="COPY (SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY 1) TO STDOUT;"
podman exec "$OLD_DB" psql -U payload -d payload -Atc "$counts_sql" > "$work/tables"
: > "$work/src-db-counts"
: > "$work/dst-db-counts"
while IFS= read -r table; do
  [ -n "$table" ] || continue
  src="$(podman exec "$OLD_DB" psql -U payload -d payload -Atc "SELECT count(*) FROM \"$table\";")"
  dst="$(podman exec "$MIGRATE_DB" psql -U payload -d payload -Atc "SELECT count(*) FROM \"$table\";")"
  printf '%s\t%s\n' "$table" "$src" >> "$work/src-db-counts"
  printf '%s\t%s\n' "$table" "$dst" >> "$work/dst-db-counts"
done < "$work/tables"
diff -u "$work/src-db-counts" "$work/dst-db-counts"
echo "==> PostgreSQL parity: $(wc -l < "$work/tables") tables"

# ---------------------------------------------------------------------------
# MinIO -> RustFS logical S3 migration
# ---------------------------------------------------------------------------
echo "==> starting RustFS 1.0 migration target"
podman rm -f "$MIGRATE_S3" >/dev/null 2>&1 || true
podman run -d --name "$MIGRATE_S3" --network host \
  -e RUSTFS_ACCESS_KEY=minio -e RUSTFS_SECRET_KEY=payload123456 \
  -e "RUSTFS_ADDRESS=:$RUSTFS_PORT" -e RUSTFS_CONSOLE_ENABLE=false \
  -e RUSTFS_REGION=us-east-1 \
  -v "$NEW_S3_VOLUME:/data" "$RUSTFS_IMAGE" /data >/dev/null
for _ in $(seq 1 60); do
  code="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$RUSTFS_PORT/health/ready" || true)"
  [ "$code" = 200 ] && break
  sleep 1
done
curl --fail --silent "http://127.0.0.1:$RUSTFS_PORT/health/ready" >/dev/null

# The old MinIO image contains mc. host.containers.internal reaches RustFS on
# the rootless host network from the old container's pasta network.
podman exec -e "RUSTFS_PORT=$RUSTFS_PORT" "$OLD_S3" sh -lc '
  mc alias set src http://127.0.0.1:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null
  mc alias set dst "http://host.containers.internal:${RUSTFS_PORT}" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null
  mc mb --ignore-existing dst/qrcodes-media >/dev/null
  mc mirror --overwrite --remove src/qrcodes-media dst/qrcodes-media
'

podman exec "$OLD_S3" sh -lc 'mc ls --recursive --json src/qrcodes-media' \
  | jq -r 'select(.type=="file") | [.key, (.size|tostring)] | @tsv' | sort > "$work/src-objects"
podman exec "$OLD_S3" sh -lc 'mc ls --recursive --json dst/qrcodes-media' \
  | jq -r 'select(.type=="file") | [.key, (.size|tostring)] | @tsv' | sort > "$work/dst-objects"
diff -u "$work/src-objects" "$work/dst-objects"
src_objects="$(wc -l < "$work/src-objects")"
src_bytes="$(awk -F '\t' '{s+=$2} END{print s+0}' "$work/src-objects")"
echo "==> S3 parity: $src_objects objects / $src_bytes bytes"

if [ "$VERIFY_ONLY" = 1 ]; then
  success=1
  echo "==> VERIFY ONLY complete — source stack untouched; target volumes retained for inspection"
  exit 0
fi

# Stop source services only after both parity checks pass. Keep source
# containers and anonymous volumes for instant rollback. Release target volumes
# from the temporary migration containers BEFORE the managed units mount them.
podman stop -t 20 "$OLD_DB" "$OLD_S3" >/dev/null
podman rm -f "$MIGRATE_DB" "$MIGRATE_S3" >/dev/null
systemctl --user start qrcode-dev-app.service
success=1
echo "==> migration complete — old containers stopped (not removed); qrcode-dev-app running + boot-linked"
