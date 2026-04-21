#!/usr/bin/env bash
set -euo pipefail

STACK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gloo"
HB_PSQL_WRAPPER_DIR="$HOME/.local/dev-bin"
HB_PSQL_WRAPPER="$HB_PSQL_WRAPPER_DIR/psql"

render_env() {
  "$STACK_DIR/systemd/render-runtime-env.sh" "$1" >/dev/null
}

source_runtime_env() {
  set -a
  # shellcheck disable=SC1090
  source "$RUNTIME_DIR/$1.env"
  set +a
}

echo "Stopping Gloo app units before schema/seed work..."
systemctl --user stop \
  gloo-gpl.service \
  gloo-hb-api.service \
  gloo-storyhub.service \
  gloo-storyhub-worker.service \
  gloo-polymer.service >/dev/null 2>&1 || true

echo "Ensuring shared databases exist..."
"$STACK_DIR/init-db.sh"

echo "Rendering runtime env files..."
for svc in gpl hb-api storyhub polymer; do
  render_env "$svc"
done

echo "Bootstrapping GPL..."
cd "$HOME/Gloo/360-gpl"
source_runtime_env gpl
pnpm db:push
pnpm db:seed

echo "Bootstrapping Hummingbird API (dump restore + migrations + dev users)..."
mkdir -p "$HB_PSQL_WRAPPER_DIR"
cat > "$HB_PSQL_WRAPPER" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
args=("$@")
if [[ ${#args[@]} -gt 0 && "${args[0]}" == postgresql://* ]]; then
  args=("${args[@]:1}")
fi
file=""
out=()
i=0
while [[ $i -lt ${#args[@]} ]]; do
  if [[ "${args[$i]}" == "-f" && $((i+1)) -lt ${#args[@]} ]]; then
    file="${args[$((i+1))]}"
    i=$((i+2))
    continue
  fi
  out+=("${args[$i]}")
  i=$((i+1))
done
if [[ -n "$file" ]]; then
  exec podman exec -i gloo_postgres_1 psql -U postgres -d postgres "${out[@]}" < "$file"
else
  exec podman exec -i gloo_postgres_1 psql -U postgres -d postgres "${out[@]}"
fi
EOF
chmod +x "$HB_PSQL_WRAPPER"
cd "$HOME/Gloo/360-hummingbird"
source_runtime_env hb-api
PATH="$HB_PSQL_WRAPPER_DIR:$HOME/.local/bin:$PATH" pnpm --filter api seed

echo "Bootstrapping Storyhub..."
cd "$HOME/Gloo/360-hummingbird/storyhub-prisma"
source_runtime_env storyhub
pnpm seed

echo "Bootstrapping Polymer..."
cd "$HOME/Gloo/360-polymer/apps/polymer"
export PATH="/home/linuxbrew/.linuxbrew/opt/node@24/bin:$PATH"
source_runtime_env polymer
pnpm db:push
pnpm db:seed

echo
echo "Bootstrap complete. Start app units with:"
echo "  systemctl --user start gloo-gpl.service"
echo "  systemctl --user start gloo-hummingbird.target"
echo "  systemctl --user start gloo-storyhub.target"
echo "  systemctl --user start gloo-polymer.service"
