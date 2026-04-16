#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="${HOME}/Code/bs/buildspace"
COMPOSE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "${REPO_DIR}/.env" ]]; then
    echo "ERROR: ${REPO_DIR}/.env not found"
    exit 1
fi

echo "=== Starting buildspace postgres ==="
podman compose -f "${COMPOSE_DIR}/compose.yaml" up -d postgres

echo "=== Waiting for postgres to be healthy ==="
for i in $(seq 1 60); do
    if podman exec buildspace-postgres-1 pg_isready -U postgres -d postgres &>/dev/null; then
        echo "Postgres is ready"
        break
    fi
    sleep 2
done

eval "$(python3 -c "from pathlib import Path; from urllib.parse import urlparse; lines = Path('${REPO_DIR}/.env').read_text().splitlines(); database_url = next((line.split('=', 1)[1].strip().strip(chr(34)).strip(chr(39)) for line in lines if line.startswith('DATABASE_URL=')), '');
if not database_url: raise SystemExit('DATABASE_URL is required');
parsed = urlparse(database_url);
shell_quote = lambda value: \"'\" + value.replace(\"'\", \"'\\''\") + \"'\";
print(f'DB_USER={shell_quote(parsed.username or \"\")}');
print(f'DB_PASS={shell_quote(parsed.password or \"\")}');
print(f'DB_NAME={shell_quote(parsed.path.lstrip(\"/\"))}')")"

if [ -z "$DB_USER" ] || [ -z "$DB_NAME" ]; then
    echo "Failed to resolve database credentials from .env" >&2
    exit 1
fi

echo "=== Creating database role and database ==="
podman exec buildspace-postgres-1 psql -U postgres -v ON_ERROR_STOP=1 -v db_user="$DB_USER" -v db_pass="$DB_PASS" -c "DO \$\$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'db_user') THEN EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', :'db_user', :'db_pass'); END IF; END \$\$;"

if [ "$(podman exec buildspace-postgres-1 psql -U postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '$DB_NAME'")" != "1" ]; then
    podman exec buildspace-postgres-1 psql -U postgres -c "CREATE DATABASE \"$DB_NAME\" OWNER \"$DB_USER\""
fi

podman exec buildspace-postgres-1 psql -U postgres -d "$DB_NAME" -v ON_ERROR_STOP=1 -v db_user="$DB_USER" -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;" -c "DO \$\$ BEGIN EXECUTE format('ALTER SCHEMA public OWNER TO %I', :'db_user'); EXECUTE format('GRANT ALL ON SCHEMA public TO %I', :'db_user'); EXECUTE format('GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO %I', :'db_user'); EXECUTE format('GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO %I', :'db_user'); END \$\$;"

echo "=== Installing dependencies ==="
cd "${REPO_DIR}"
bun install --frozen-lockfile

echo "=== Running migrations and seed ==="
cd "${REPO_DIR}/packages/db"
bun --env-file=../../.env run db:migrate
bun --env-file=../../.env run db:seed

echo ""
echo "=== Bootstrap complete ==="
echo "Start dev servers with: cd ${REPO_DIR} && bun run dev"
echo "Or start individual services:"
echo "  bun --filter @buildspace/marketplace dev"
echo "  bun --filter @buildspace/login dev"
echo "  bun --filter @buildspace/runtime dev"
echo "  bun --filter @buildspace/studio dev"
echo "  bun --filter @buildspace/docs dev"
echo "  bun --filter @buildspace/super-admin dev"
echo "  bun --filter @buildspace/jobs-app dev"
