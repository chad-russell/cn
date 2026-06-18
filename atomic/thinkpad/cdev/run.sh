#!/usr/bin/env bash
# Enter the cdev sandbox — isolated dev/AI environment.
#
# Config (zsh, nvim, git identity) is baked into the image at
# /usr/share/crussell. Mutable state (history, agent keys, ~/.cargo, etc.)
# lives on a named Podman volume mounted at $HOME inside the container.
#
# Fork this script for new use cases before abstracting. Examples:
#   ./run.sh -w ~/Gloo/360-gpl
#   ./run.sh -w . CDEV_HOME_VOLUME=cdev-home-gpl nvim
#   CDEV_MODE=airtight ./run.sh -w ~/Code/foo pi
#   ./run.sh --workvol my-project-vol
#
# Options (mutually exclusive ways to mount /work):
#   -w, --workdir PATH  bind a host directory at /work (use "." for $PWD)
#   --workvol NAME      mount a Podman named volume at /work (long form only)
#   Omit both for a sealed sandbox (no /work mount).
#
# Short-flag convention: only -w/--workdir has a short form (-w). --workvol is
# long-only because -v collides with "verbose" on most Unix tools and -V with
# "--version"; infrequent options stay unabbreviated to stay unambiguous.
#
#   --dry-run           print the podman invocation without running it
#
# Environment:
#   CDEV_IMAGE          image ref (default: localhost/cdev:latest)
#   CDEV_HOME_VOLUME    named volume for container $HOME (default: cdev-home)
#   CDEV_WORK_PATH      in-container mount point (default: /work)
#   CDEV_MODE           root | user | airtight (default: root)
#   CDEV_SSH            set to "agent" to forward SSH_AUTH_SOCK (opt-in)
#   CDEV_EXTRA_ARGS     extra args appended to podman run (quoted string)
#
# Remaining positional args override the default command (/usr/bin/zsh -l).
set -euo pipefail

workdir=""
workvol=""
dry_run=0
cmd=()

while (($#)); do
  case "$1" in
    --dry-run)
      dry_run=1
      shift
      ;;
    -w|--workdir)
      if (($# < 2)); then
        echo "run.sh: $1 requires a path" >&2
        exit 1
      fi
      if [[ -n "$workdir" ]]; then
        echo "run.sh: -w/--workdir specified more than once" >&2
        exit 1
      fi
      workdir=$2
      shift 2
      ;;
    --workvol)
      if (($# < 2)); then
        echo "run.sh: --workvol requires a volume name" >&2
        exit 1
      fi
      if [[ -n "$workvol" ]]; then
        echo "run.sh: --workvol specified more than once" >&2
        exit 1
      fi
      workvol=$2
      shift 2
      ;;
    --)
      shift
      cmd=("$@")
      break
      ;;
    -*)
      echo "run.sh: unknown option: $1" >&2
      exit 1
      ;;
    *)
      cmd=("$@")
      break
      ;;
  esac
done

CDEV_IMAGE="${CDEV_IMAGE:-localhost/cdev:latest}"
CDEV_HOME_VOLUME="${CDEV_HOME_VOLUME:-cdev-home}"
CDEV_WORK_PATH="${CDEV_WORK_PATH:-/work}"
CDEV_MODE="${CDEV_MODE:-root}"
SANDBOX_HOME="/home/sandbox"

if [[ "$workdir" == "." ]]; then
  workdir="$PWD"
fi

if [[ -n "$workdir" && -n "$workvol" ]]; then
  echo "run.sh: --workdir and --workvol are mutually exclusive" >&2
  exit 1
fi

args=(
  --rm -it
  --security-opt no-new-privileges
  -e HOME="$SANDBOX_HOME"
  -v "${CDEV_HOME_VOLUME}:${SANDBOX_HOME}:U"
  -v "cdev-aws:${SANDBOX_HOME}/.aws"
)
# --cap-drop=ALL

case "$CDEV_MODE" in
  root)
    # Container "root" maps to your unprivileged host UID (rootless podman).
    ;;
  user)
    args+=(--userns=keep-id)
    ;;
  airtight)
    args+=(
      --network=none
      --read-only
      --tmpfs /tmp:rw,nosuid,nodev,noexec,size=512m
    )
    ;;
  *)
    echo "run.sh: unknown CDEV_MODE=$CDEV_MODE (want root, user, or airtight)" >&2
    exit 1
    ;;
esac

if [[ -n "$workvol" ]]; then
  args+=(-v "${workvol}:${CDEV_WORK_PATH}:U")
  args+=(-w "$CDEV_WORK_PATH")
elif [[ -n "$workdir" ]]; then
  project="$(cd "$workdir" && pwd)"
  args+=(-v "${project}:${CDEV_WORK_PATH}:Z")
  args+=(-w "$CDEV_WORK_PATH")
else
  args+=(-w "$SANDBOX_HOME")
fi

if [[ "${CDEV_SSH:-}" == agent ]]; then
  if [[ -n "${SSH_AUTH_SOCK:-}" && -S "$SSH_AUTH_SOCK" ]]; then
    args+=(-v "${SSH_AUTH_SOCK}:${SSH_AUTH_SOCK}:ro" -e "SSH_AUTH_SOCK=${SSH_AUTH_SOCK}")
  else
    echo "run.sh: CDEV_SSH=agent but SSH_AUTH_SOCK is not set" >&2
    exit 1
  fi
fi

if [[ -n "${CDEV_EXTRA_ARGS:-}" ]]; then
  # shellcheck disable=SC2206
  extra=( ${CDEV_EXTRA_ARGS} )
  args+=("${extra[@]}")
fi

if ((${#cmd[@]} == 0)); then
  cmd=(/usr/bin/zsh -l)
fi

if ((dry_run)); then
  printf 'podman run'
  for a in "${args[@]}" "$CDEV_IMAGE" "${cmd[@]}"; do
    printf ' %q' "$a"
  done
  printf '\n'
  exit 0
fi

exec podman run "${args[@]}" "$CDEV_IMAGE" "${cmd[@]}"
