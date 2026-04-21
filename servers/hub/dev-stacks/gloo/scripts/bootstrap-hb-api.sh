#!/usr/bin/env bash
# Bootstrap Hummingbird API: seed data via psql wrapper.
# Assumes infra is running and runtime env is already rendered.
set -euo pipefail

RUNTIME_BASE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gloo"
HB_PSQL_WRAPPER_DIR="$HOME/.local/dev-bin"
HB_PSQL_WRAPPER="$HB_PSQL_WRAPPER_DIR/psql"
export PATH="/home/linuxbrew/.linuxbrew/opt/node@24/bin:$HOME/.local/bin:$HOME/.bun/bin:$PATH"

set -a
# shellcheck disable=SC1090
source "$RUNTIME_BASE/hb-api.env"
set +a

# Create a psql wrapper that routes through the compose postgres container.
mkdir -p "$HB_PSQL_WRAPPER_DIR"
cat > "$HB_PSQL_WRAPPER" <<'WRAPPER'
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
WRAPPER
chmod +x "$HB_PSQL_WRAPPER"

cd "$HOME/Gloo/360-hummingbird"
PATH="$HB_PSQL_WRAPPER_DIR:$PATH" pnpm --filter api seed
