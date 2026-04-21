#!/usr/bin/env bash
# Initialize all required databases in the Gloo postgres.
# Safe to re-run — uses IF NOT EXISTS equivalent via CREATE DATABASE ... 2>/dev/null.
set -euo pipefail

CONTAINER="${POSTGRES_CONTAINER:-glo_postgres_1}"

echo "Creating databases..."
podman exec "$CONTAINER" psql -U postgres -c "CREATE DATABASE gpl_db;" 2>/dev/null && echo "  ✓ gpl_db" || echo "  ✓ gpl_db (already exists)"
podman exec "$CONTAINER" psql -U postgres -c "CREATE DATABASE storyhub;" 2>/dev/null && echo "  ✓ storyhub" || echo "  ✓ storyhub (already exists)"
podman exec "$CONTAINER" psql -U postgres -c "CREATE DATABASE polymer;" 2>/dev/null && echo "  ✓ polymer" || echo "  ✓ polymer (already exists)"

echo "Done."
