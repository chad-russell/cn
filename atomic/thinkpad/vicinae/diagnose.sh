#!/usr/bin/env bash
#
# ARCHIVED container-based Vicinae helper.
# Current production path is host `vicinae` + `image/vicinae-bwrap`; see
# `vicinae/README.md`.
#
# Diagnose the vicinae container: scrolling env var + flatpak discovery.
# Run on the HOST.  Reads the ACTUAL server process env (PID 1), not the config.
#
set -uo pipefail
C="${VICINAE_CONTAINER:-vicinae}"
P(){ printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }
run(){ echo "\$ podman exec $C $*"; podman exec "$C" "$@"; echo; }

P "0) Is the container even running?"
podman ps --filter "name=^${C}\$" --format '{{.Names}}  {{.Status}}  {{.Image}}  (started {{.RunningFor}})' || true

P "1) SCROLLING: is the env var in the SERVER process (PID 1)?  <-- the real test"
echo "If this prints nothing, the container was started from an OLD run.sh."
podman exec "$C" sh -c "tr '\0' '\n' < /proc/1/environ | grep -i 'QT_QUICK\|QT_QPA\|QT_WAYLAND'" || true

P "2) FLATPAK: was the image rebuilt with the /usr/bin/flatpak shim?"
echo "(TryExec=/usr/bin/flatpak must resolve to an executable for flatpaks to show.)"
podman exec "$C" sh -c 'ls -l /usr/bin/flatpak /usr/local/bin/flatpak /usr/local/bin/host-spawn 2>&1; test -x /usr/bin/flatpak && echo "EXECUTABLE: yes" || echo "EXECUTABLE: NO <- rebuild image!"' || true

P "3) FLATPAK: are the host flatpak export dirs mounted & populated?"
echo "XDG_DATA_DIRS seen by server:"
podman exec "$C" sh -c 'tr "\0" "\n" < /proc/1/environ | grep ^XDG_DATA_DIRS' || true
echo "Flatpak export applications dirs:"
podman exec "$C" sh -c 'for d in /var/lib/flatpak/exports/share/applications '"${HOME}"'/.local/share/flatpak/exports/share/applications; do echo "--- $d ---"; ls "$d" 2>&1 | head -8; done' || true

P "4) FLATPAK: what TryExec does a real flatpak .desktop have here?"
podman exec "$C" sh -c 'f=$(ls /var/lib/flatpak/exports/share/applications/*.desktop 2>/dev/null | head -1); echo "file: $f"; grep -E "^(Name|TryExec|Exec|NoDisplay|Hidden)=" "$f" 2>&1' || true

P "5) FLATPAK: does vicinae's app database actually contain flatpaks? (definitive)"
echo "Counts below come from the dirs vicinae scans (XDG_DATA_DIRS/applications)."
podman exec "$C" sh -c '
  total=0
  for d in $(tr "\0" "\n" < /proc/1/environ | sed -n "s/^XDG_DATA_DIRS=//p" | tr ":" "\n"); do
    a="$d/applications";
    n=$(ls "$a"/*.desktop 2>/dev/null | wc -l);
    echo "  $a -> $n desktop files";
    total=$((total+n));
  done;
  echo "TOTAL visible to vicinae: $total"' || true

P "6) Any scan errors / warnings in the server log?"
podman logs --tail 40 "$C" 2>&1 | grep -iE 'desktop|flatpak|invalid|scan|error|warn' || echo "(no matching log lines)"

echo
echo "=== If section 1 printed nothing -> restart: ./run.sh  (after rebuilding: podman build ...)"
echo "=== If section 2 said EXECUTABLE: NO -> rebuild image: podman build -t localhost/vicinae:latest -f Containerfile ."
