#!/usr/bin/env bash
set -euo pipefail

failures=0

check_cmd() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    printf '[ok] %s\n' "$cmd"
  else
    printf '[missing] command: %s\n' "$cmd"
    failures=$((failures + 1))
  fi
}

check_path() {
  local path="$1"
  if [[ -e "$path" ]]; then
    printf '[ok] %s\n' "$path"
  else
    printf '[missing] %s\n' "$path"
    failures=$((failures + 1))
  fi
}

check_cmd_path() {
  local label="$1"
  local path="$2"
  if [[ -x "$path" ]]; then
    printf '[ok] %s (%s)\n' "$label" "$path"
  else
    printf '[missing] %s (%s)\n' "$label" "$path"
    failures=$((failures + 1))
  fi
}

check_cmd_path brunch "$HOME/.local/share/brioche/installed/bin/brunch"
check_cmd_path brioche "$HOME/.local/share/brioche-install/brioche/current/bin/brioche"
check_cmd podman

check_path "$HOME/Code/cn"
check_path "$HOME/Code/bs/buildspace"
check_path "$HOME/Gloo/gloo-control-plane"
check_path "$HOME/Gloo/360-gpl"
check_path "$HOME/Gloo/360-hummingbird"
check_path "$HOME/Gloo/360-polymer"

check_path "$HOME/Code/bs/buildspace/.env"
check_path "$HOME/.config/buildspace/buildspace.env"

check_path "$HOME/Gloo/gloo-control-plane/envs/systemd-local.env"
check_path "$HOME/Gloo/gloo-control-plane/envs/gpl.env"
check_path "$HOME/Gloo/gloo-control-plane/envs/hb-api.env"
check_path "$HOME/Gloo/gloo-control-plane/envs/hb-web.env"
check_path "$HOME/Gloo/gloo-control-plane/envs/polymer.env"
check_path "$HOME/Gloo/gloo-control-plane/envs/pgadmin.env"

if (( failures > 0 )); then
  printf '\nPreflight failed with %d missing prerequisite(s).\n' "$failures"
  exit 1
fi

printf '\nPreflight passed. Ready for `brunch apply ./brunch/config --target hub`.\n'
