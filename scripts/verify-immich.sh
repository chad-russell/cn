#!/usr/bin/env bash
# verify-immich.sh — post-cutover verification for the immich-loop migration.
#
# Gates the H1 cutover and the 7-day soak on bees (immich-loop board, task B2).
# Exit 0 only if every applicable check passes.
#
# Usage (on bees, from the cn repo root):
#   sudo -E ./scripts/verify-immich.sh                       # read-only checks
#   sudo -E ./scripts/verify-immich.sh --mode upload         # + upload/album/delete smoke test
#   sudo -E ./scripts/verify-immich.sh --record              # read-only + write soak baseline
#   sudo -E ./scripts/verify-immich.sh --json                # machine-readable (cron/watchdog)
#
# Auth (pick ONE):
#   IMMICH_EMAIL + IMMICH_PASSWORD   session login  (POST /auth/login)
#   IMMICH_API_KEY                   API key        (header x-api-key)
#   Neither  -> auth/db/upload checks SKIP (exit stays 0 if everything else passes)
#
# Env overrides:
#   IMMICH_URL    default http://127.0.0.1:2283/api
#   IMMICH_EXPECT_VERSION  default 3.1.0 (rollback verification: set 2.7.5)
#   IMMICH_VERIFY_BASELINE  baseline counts (json '{"albums":N,"assets":N}') — skips state file
#
# Endpoints verified against the immich v3.1.0 OpenAPI spec
# (open-api/immich-openapi-specs.json @ tag v3.1.0): /server/ping /server/version
# /auth/login /auth/validateToken /users/me /albums /assets (POST/DELETE)
# /albums/{id}/assets /search/smart.
#
# NOTE (B1 dry-run): quadlet unit names may differ from the placeholder below.
# Runbook §5 step 1 discovers them; adjust UNIT_PATTERNS if needed.
#   TODO-B1(dry-run): confirm final unit names for the prod quadlets.

set -uo pipefail

IMMICH_URL="${IMMICH_URL:-http://127.0.0.1:2283/api}"
API="${IMMICH_URL%/}"
EXPECT_VERSION="${IMMICH_EXPECT_VERSION:-3.1.0}"
IMMICH_EMAIL="${IMMICH_EMAIL:-}"
IMMICH_PASSWORD="${IMMICH_PASSWORD:-}"
IMMICH_API_KEY="${IMMICH_API_KEY:-}"
MODE="read"
RECORD=0
JSON=0
ALBUM_NAME="loop-verify-$(date -u +%Y%m%dT%H%M%SZ)"
KEEP_ALBUM=0
STATE_FILE="/var/tmp/immich-verify-state.json"
BASELINE_OVERRIDE="${IMMICH_VERIFY_BASELINE:-}"
# Unit names: podman-systemd-generator turns immich-server.container into
# systemd-immich-server.service (container "immich-server"); same for ML.
UNIT_PATTERNS_SERVER=("immich-server.service" "systemd-immich-server.service")
UNIT_PATTERNS_ML=("immich-machine-learning.service" "systemd-immich-machine-learning.service")
SERVER_CONTAINERS=("immich-server" "systemd-immich-server")
MIN_ASSETS=1000   # sanity floor: the real library is far larger

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --mode) MODE="${2:?}"; shift 2 ;;
    --record) RECORD=1; shift ;;
    --json) JSON=1; shift ;;
    --album) ALBUM_NAME="${2:?}"; shift 2 ;;
    --keep-album) KEEP_ALBUM=1; shift ;;
    --url) IMMICH_URL="${2:?}"; API="${IMMICH_URL%/}"; shift 2 ;;
    -h|--help) usage 0 ;;
    *) echo "unknown arg: $1" >&2; usage 1 ;;
  esac
done

PASS=0; FAIL=0; SKIP=0
emit() { # emit <PASS|FAIL|SKIP> <check> <detail>
  if [ "$JSON" -eq 1 ]; then
    printf '{"check":"%s","status":"%s","detail":"%s"}\n' "$2" "$1" "$3"
  else
    printf '  %-4s %-24s %s\n' "$1" "$2" "$3"
  fi
}
ok()   { PASS=$((PASS+1)); emit PASS "$1" "$2"; }
bad()  { FAIL=$((FAIL+1)); emit FAIL "$1" "$2"; }
skip() { SKIP=$((SKIP+1)); emit SKIP "$1" "$2"; }

need() { command -v "$1" >/dev/null 2>&1 || { echo "FATAL: missing dependency: $1" >&2; exit 2; }; }
need curl; need jq; need systemctl

trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }

[ "$(id -u)" -eq 0 ] || echo "note: not root — systemctl/podman checks may be restricted" >&2

header() { [ "$JSON" -eq 0 ] && printf '\n== %s ==\n' "$1" || true; }

# http METHOD PATH [JSON_BODY] [AUTH: 1|0] -> sets BODY / CODE
BODY=""; CODE=""
http() {
  local method="$1" path="$2" data="${3:-}" auth="${4:-1}"
  local args=(-sS -X "$method" "$API$path" -H 'Content-Type: application/json'
              --max-time 30 -w '\n%{http_code}')
  [ -n "$TOKEN_HEADER" ] && [ "$auth" = 1 ] && args+=(-H "$TOKEN_HEADER")
  [ -n "$data" ] && args+=(-d "$data")
  local out; out=$(curl "${args[@]}" 2>&1) || true
  CODE="${out##*$'\n'}"
  BODY="${out%$'\n'*}"
}

first_active_unit() { # prints the first matching active unit name, else empty
  local pat
  for pat in "$@"; do
    if systemctl is-active --quiet "$pat" 2>/dev/null; then printf '%s' "$pat"; return 0; fi
  done
  return 1
}

TOKEN_HEADER=""

CUTOVER_MODE=1; [ "$EXPECT_VERSION" = "3.1.0" ] || CUTOVER_MODE=0   # 0 = module/rollback mode

## 1. Service units ──────────────────────────────────────────────────────────
header "systemd units"
SERVER_UNIT="$(first_active_unit "${UNIT_PATTERNS_SERVER[@]}" || true)"
if [ -n "$SERVER_UNIT" ]; then ok units "server: $SERVER_UNIT active"
else bad units "no active unit among: ${UNIT_PATTERNS_SERVER[*]} — systemctl list-unit-files 'immich*'"
fi
ML_UNIT="$(first_active_unit "${UNIT_PATTERNS_ML[@]}" || true)"
if [ -n "$ML_UNIT" ]; then ok units "ml: $ML_UNIT active"
else bad units "no active unit among: ${UNIT_PATTERNS_ML[*]}"
fi
# Cutover mode: the legacy native module unit must NOT shadow the quadlet.
# Discriminator (verified live on bees): quadlet-generated units show
#   SourcePath=/etc/containers/systemd/*.container  FragmentPath=/run/systemd/generator/…
# the native module's unit (or a leftover NixOS stub) has FragmentPath under
# /etc/systemd/system and NO SourcePath. NB: `systemctl cat` is unusable as a
# guard here (exit 141 SIGPIPE quirk) — use FragmentPath instead.
FRAG="$(systemctl show -P FragmentPath immich-server.service 2>/dev/null)"
if [ -n "$FRAG" ] && [ "$CUTOVER_MODE" -eq 1 ]; then
  SRC="$(systemctl show -P SourcePath immich-server.service 2>/dev/null)"
  if [ -z "$SRC" ]; then
    bad units "immich-server.service exists WITHOUT a .container SourcePath — services.immich still enabled, or the old NixOS stub unit was not removed (see RUNBOOK §4)"
  fi
fi

## 2. Container backends ──────────────────────────────────────────────────────
header "containers"
PODMAN_BIN=""
if command -v podman >/dev/null 2>&1; then PODMAN_BIN=podman
elif command -v docker >/dev/null 2>&1; then PODMAN_BIN=docker
else skip containers "no podman/docker CLI — skipping container inspection"
fi
if [ -n "$PODMAN_BIN" ]; then
  if [ "$CUTOVER_MODE" -eq 0 ]; then
    skip containers "module/rollback mode — container pin not checked"
  else
  SC=""; for c in "${SERVER_CONTAINERS[@]}"; do
    if sudo -n "$PODMAN_BIN" inspect "$c" >/dev/null 2>&1; then SC="$c"; break; fi
  done
  if [ -n "$SC" ]; then
    IMG="$(sudo -n "$PODMAN_BIN" inspect -f '{{.Config.Image}}' "$c" 2>/dev/null || echo '?')"
    RUN="$(sudo -n "$PODMAN_BIN" inspect -f '{{.State.Status}}' "$c" 2>/dev/null || echo '?')"
    case "$IMG" in *:v3.1.0) ok image "$SC running $IMG ($RUN)" ;;
      *) bad image "$SC image is '$IMG' — expected ghcr.io/immich-app/*:v3.1.0 (pin D1)" ;;
    esac
  else bad containers "no server container among: ${SERVER_CONTAINERS[*]}"
  fi
  fi
fi

## 3. API up ──────────────────────────────────────────────────────────────────
header "api"
http GET /server/ping "" 0
PING_RES="$(printf %s "$BODY" | jq -r '.res // empty' 2>/dev/null || true)"
if [ "$CODE" = 200 ] && [ "$PING_RES" = "pong" ]; then ok ping "GET /server/ping -> {\"res\":\"pong\"}"
else
  # retry once — first request after start can be slow
  sleep 3; http GET /server/ping "" 0
  PING_RES="$(printf %s "$BODY" | jq -r '.res // empty' 2>/dev/null || true)"
  if [ "$CODE" = 200 ] && [ "$PING_RES" = "pong" ]; then ok ping "GET /server/ping -> {\"res\":\"pong\"} (2nd try)"
  else bad ping "GET /server/ping -> HTTP ${CODE:-none} body='$(printf %s "$BODY" | head -c 120)'"
  fi
fi

http GET /server/version "" 0
# v3 spec: ServerVersionResponseDto {major, minor, patch, prerelease}
VERSION="$(printf %s "$BODY" | jq -r 'if .major then "\(.major).\(.minor).\(.patch)" else .version // empty end' 2>/dev/null || true)"
if [ "$CODE" = 200 ] && [ "$VERSION" = "$EXPECT_VERSION" ]; then ok version "server reports v$VERSION"
elif [ "$CODE" = 200 ]; then bad version "server reports '${VERSION:-?}' — expected $EXPECT_VERSION"
else bad version "GET /server/version -> HTTP ${CODE:-none}"
fi

## 4. Auth ────────────────────────────────────────────────────────────────────
header "auth"
if [ -n "$IMMICH_API_KEY" ]; then
  TOKEN_HEADER="x-api-key: $IMMICH_API_KEY"
  http GET /users/me
  if [ "$CODE" = 200 ]; then ok auth "api key accepted ($(printf %s "$BODY" | jq -r '.email // "?"'))"
  else bad auth "api key rejected: HTTP $CODE $(printf %s "$BODY" | head -c 120)"
  fi
elif [ -n "$IMMICH_EMAIL" ] && [ -n "$IMMICH_PASSWORD" ]; then
  CREDS="$(jq -nc --arg e "$IMMICH_EMAIL" --arg p "$IMMICH_PASSWORD" '{email:$e,password:$p}')"
  http POST /auth/login "$CREDS" 0
  TOKEN="$(printf %s "$BODY" | jq -r '.accessToken // empty' 2>/dev/null || true)"
  if [ "$CODE" = 201 ] && [ -n "$TOKEN" ]; then
    TOKEN_HEADER="Authorization: Bearer $TOKEN"
    ok auth "login ok as $IMMICH_EMAIL"
    http POST /auth/validateToken
    [ "$CODE" = 200 ] && ok auth "token validates" || bad auth "validateToken -> HTTP $CODE"
  else bad auth "login failed: HTTP ${CODE:-none} $(printf %s "$BODY" | head -c 120)"
  fi
else
  skip auth "IMMICH_EMAIL/IMMICH_PASSWORD or IMMICH_API_KEY not set"
fi

AUTHED=0
[ -n "$TOKEN_HEADER" ] && AUTHED=1

## 5. DB-backed counts ────────────────────────────────────────────────────────
header "database (via API)"
ALBUMS=-1; ASSETS=-1
if [ "$AUTHED" -eq 1 ]; then
  http GET /albums
  if [ "$CODE" = 200 ]; then
    ALBUMS="$(printf %s "$BODY" | jq 'length' 2>/dev/null || echo -1)"
    [ "$ALBUMS" -ge 0 ] && ok albums "GET /albums -> $ALBUMS albums" || bad albums "albums parse failed"
  else bad albums "GET /albums -> HTTP $CODE"
  fi
  http GET /assets/statistics
  if [ "$CODE" = 200 ]; then
    ASSETS="$(printf %s "$BODY" | jq -r '.total // -1' 2>/dev/null || echo -1)"
    if [ "$ASSETS" -ge "$MIN_ASSETS" ]; then ok assets "library has $ASSETS assets (floor $MIN_ASSETS)"
    else bad assets "only $ASSETS assets — below sanity floor $MIN_ASSETS (data loss?)"
    fi
  else bad assets "GET /assets/statistics -> HTTP $CODE"
  fi
else skip albums "no auth"; skip assets "no auth"
fi

## 5b. DB integrity via psql (needs sudo -n -u postgres) ────────────────────
header "database (psql)"
EXPECTED_PG_EXTENSIONS="${EXPECTED_PG_EXTENSIONS:-cube,earthdistance,pg_trgm,unaccent,uuid-ossp,vector,vchord}"
if sudo -n -u postgres psql -Atc 'select 1' >/dev/null 2>&1; then
  DB_LIST="$(sudo -n -u postgres psql -Atc "select datname from pg_database where datistemplate=false" 2>/dev/null | sort | tr '\n' ' ')"
  case " $DB_LIST " in
    *" immich "*) ok db "databases: $DB_LIST" ;;
    *) bad db "immich database MISSING (present: ${DB_LIST:-none})" ;;
  esac
  ROLE="$(sudo -n -u postgres psql -Atc "select rolname from pg_roles where rolname='immich'" 2>/dev/null)"
  [ "$ROLE" = "immich" ] && ok db "role immich exists" || bad db "role immich missing"
  PG_EXTS="$(sudo -n -u postgres psql -d immich -Atc 'select extname from pg_extension order by 1' 2>/dev/null | tr '\n' ' ')"
  MISSING=""
  OLDIFS="$IFS"; IFS=','
  for e in $EXPECTED_PG_EXTENSIONS; do
    case " $PG_EXTS " in *" $e "*) ;; *) MISSING="$MISSING $e" ;; esac
  done
  IFS="$OLDIFS"
  if [ -z "$(trim "$MISSING")" ]; then
    ok db "pg extensions present: $PG_EXTS"
  else
    bad db "missing extensions:$MISSING (have:$PG_EXTS) — restore per RUNBOOK §3"
  fi
else
  skip db "sudo -n -u postgres psql unavailable"
fi

## 6. Baseline / drift ────────────────────────────────────────────────────────
header "soak baseline"
BASELINE=""
if [ -n "$BASELINE_OVERRIDE" ]; then BASELINE="$BASELINE_OVERRIDE"
elif [ -f "$STATE_FILE" ]; then BASELINE="$(cat "$STATE_FILE" 2>/dev/null || true)"
fi
if [ "$RECORD" -eq 1 ]; then
  if [ "$ALBUMS" -ge 0 ] && [ "$ASSETS" -ge 0 ]; then
    umask 077
    printf '{"recorded":"%s","albums":%s,"assets":%s}\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$ALBUMS" "$ASSETS" > "$STATE_FILE" || true
    ok record "baseline written to $STATE_FILE (albums=$ALBUMS assets=$ASSETS)"
  else bad record "cannot record baseline — counts unavailable"
  fi
elif [ -n "$BASELINE" ]; then
  B_ALBUMS="$(printf %s "$BASELINE" | jq -r '.albums // -1' 2>/dev/null || echo -1)"
  B_ASSETS="$(printf %s "$BASELINE" | jq -r '.assets // -1' 2>/dev/null || echo -1)"
  DRIFT_OK="$(jq -n --argjson a "$ASSETS" --argjson b "$B_ASSETS" \
    'if $a >= 0 and $b >= 0 then ($a >= ($b * 0.95)) else false end' 2>/dev/null || echo false)"
  if [ "$DRIFT_OK" = true ]; then
    ok drift "assets $B_ASSETS -> $ASSETS (baseline ±5% ok; albums $B_ALBUMS -> $ALBUMS)"
  else bad drift "assets $B_ASSETS -> $ASSETS — drifted >5% below baseline (albums $B_ALBUMS -> $ALBUMS)"
  fi
else skip baseline "no baseline recorded yet (run --record once after cutover)"
fi

## 7. ML pipeline ─────────────────────────────────────────────────────────────
header "machine learning"
if [ "$AUTHED" -eq 1 ]; then
  http POST /search/smart '{"query":"person human","page":1,"size":1}'
  if [ "$CODE" = 200 ]; then
    N="$(printf %s "$BODY" | jq -r '.assets.total // (.assets.objects | length) // 0' 2>/dev/null || echo 0)"
    ok ml "smart search (CLIP via ML) responded — page total=$N"
  else bad ml "POST /search/smart -> HTTP $CODE $(printf %s "$BODY" | head -c 160)"
  fi
else skip ml "no auth"
fi

## 8. Upload smoke (opt-in) ───────────────────────────────────────────────────
if [ "$MODE" = upload ]; then
  header "upload smoke (writes!)"
  if [ "$AUTHED" -ne 1 ]; then
    skip upload "no credentials — cannot run upload smoke"
  else
    TMP="$(mktemp /tmp/immich-verify-XXXXXX.jpg)"
    trap 'rm -f "$TMP"' EXIT
    # unique bytes each run -> never trips duplicate detection (v3 keys by checksum)
    # P1 ASCII bitmap with a random comment line (legal in PBM) => unique file
    { printf 'P1\n# '; head -c 64 /dev/urandom | base64 | tr -d '\n'; printf '\n2 2\n1 0 0 1\n'; } > "$TMP"
    NOW="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
    UP_OUT="$(curl -sS -X POST "$API/assets" \
      -H "$TOKEN_HEADER" \
      -F "assetData=@$TMP;type=image/jpeg;filename=loop-verify.jpg" \
      -F "filename=loop-verify.jpg" -F "fileCreatedAt=$NOW" -F "fileModifiedAt=$NOW" \
      --max-time 60 -w '\n%{http_code}' 2>&1)" || true
    UP_CODE="${UP_OUT##*$'\n'}"; UP_BODY="${UP_OUT%$'\n'*}"
    ASSET_ID="$(printf %s "$UP_BODY" | jq -r '.id // empty' 2>/dev/null || true)"
    if [ "$UP_CODE" = 201 ] && [ -n "$ASSET_ID" ]; then
      ok upload "uploaded asset $ASSET_ID"
    else bad upload "upload failed: HTTP ${UP_CODE:-none} $(printf %s "$UP_BODY" | head -c 160)"; fi

    ALBUM_ID=""
    if [ "$KEEP_ALBUM" -eq 1 ]; then
      http GET /albums
      ALBUM_ID="$(printf %s "$BODY" | jq -r --arg n "$ALBUM_NAME" '.[] | select(.albumName==$n) | .id // empty' 2>/dev/null || true)"
    fi
    if [ -z "$ALBUM_ID" ]; then
      http POST /albums "$(jq -nc --arg n "$ALBUM_NAME" '{albumName:$n}')"
      ALBUM_ID="$(printf %s "$BODY" | jq -r '.id // empty' 2>/dev/null || true)"
    fi
    if [ -n "$ALBUM_ID" ]; then
      ok album "test album '$ALBUM_NAME' ($ALBUM_ID)"
      if [ -n "$ASSET_ID" ]; then
        http PUT "/albums/$ALBUM_ID/assets" "$(jq -nc --arg i "$ASSET_ID" '{ids:[$i]}')"
        ADDED="$(printf %s "$BODY" | jq -r --arg i "$ASSET_ID" '.[$i].success // false' 2>/dev/null || echo false)"
        [ "$ADDED" = true ] && ok album "asset added to album" \
                          || bad album "add-to-album: HTTP $CODE $(printf %s "$BODY" | head -c 120)"
      fi
    else bad album "album create failed: HTTP $CODE $(printf %s "$BODY" | head -c 120)"
    fi

    if [ -n "$ASSET_ID" ]; then
      http DELETE /assets "$(jq -nc --arg i "$ASSET_ID" '{ids:[$i],force:true}')"
      # v3.1.0: DELETE /assets returns 204 No Content (no body)
      case "$CODE" in
        200|204) ok cleanup "test asset hard-deleted (force, HTTP $CODE)" ;;
        *) bad cleanup "asset delete: HTTP $CODE $(printf %s "$BODY" | head -c 120)" ;;
      esac
    fi
    if [ -n "$ALBUM_ID" ] && [ "$KEEP_ALBUM" -eq 0 ]; then
      http DELETE "/albums/$ALBUM_ID"
      case "$CODE" in
        200|204) ok cleanup "test album deleted (HTTP $CODE)" ;;
        *) bad cleanup "album delete: HTTP $CODE $(printf %s "$BODY" | head -c 120)" ;;
      esac
    fi
  fi
fi

## summary ────────────────────────────────────────────────────────────────────
if [ "$JSON" -eq 0 ]; then
  printf '\nSummary: %d pass, %d fail, %d skip\n' "$PASS" "$FAIL" "$SKIP"
  [ "$FAIL" -eq 0 ] && printf 'RESULT: PASS\n' || printf 'RESULT: FAIL\n'
  [ "$FAIL" -gt 0 ] && printf 'Investigate on bees: journalctl -u immich-* ; podman logs immich-server\n'
else
  printf '{"summary":{"pass":%d,"fail":%d,"skip":%d},"result":"%s","url":"%s","ts":"%s"}\n' \
    "$PASS" "$FAIL" "$SKIP" "$([ "$FAIL" -eq 0 ] && echo PASS || echo FAIL)" \
    "$API" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
fi
exit $(( FAIL > 0 ? 1 : 0 ))
