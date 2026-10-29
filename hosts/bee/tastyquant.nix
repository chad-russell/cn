# ── bee: tastyquant (trades.internal.crussell.io) ───────────────────
#
# Chad's options quant desk v2 — repo git.crussell.io/chad/tastyquant,
# checkout ~/tastyquant. Serves the chat desk (apps/desk, Next.js) on
# 10.10.0.12:3320 → https://trades.internal.crussell.io (bees Caddy).
#
# Declarative since 2026-10-23 (replaces the hand-written user units in
# ~/.config/systemd/user and the v1 ~/tasty_options stack — trades-site.nix,
# removed same day). Units wrap the repo's own launcher `tools/tq`
# (desk | gateway | market), which builds + (re)starts the rootless
# tq-* podman containers; `tools/tq <cmd> --stop` is the ExecStop.
#
# State lives in ~/tastyquant-data (moved out of the checkout 2026-10-24):
# v2 portfolio.db + executor audit db + logs/corpora; pre-move snapshot in
# tastyquant-data/pre-move-snapshot-2026-10-24/.
#
# Credentials (agenix, never in the tastyquant repo):
#   secrets/tastyquant-env.age → TT_SECRET, TT_REFRESH,
#     TASTYTRADE_PRODUCTION, MARKETDATA_APP_KEY — materialized as
#     ~/tastyquant/.env and ~/tastyquant/.env.production (crussell 0600)
#     by tastyquant-env-deploy.service below.
#   .env.desk = NINEROUTER_API_KEY=<Z.AI coding-plan key> — the desk's
#     chat LLM env var is legacy-named in apps/desk, but since
#     2026-10-23 it points DIRECTLY at the Z.AI coding plan (no
#     9router — decommissioned same day): TQ_LLM_BASE_URL below
#     overrides the code default.
#
# Timers (weekdays, America/New_York): scan 10:15, capture 17:10,
# sweep 17:35.

{ config, lib, pkgs, ... }:

let
  repo = "/home/crussell/tastyquant";
  # Image-run oneshot: dist is baked into the zot image — no checkout,
  # no pnpm build. Data + read-only .env bind exactly as tools/tq did.
  imageRun = cli: ''
    ${pkgs.podman}/bin/podman run --rm --user 0:0 \
      -v /home/crussell/tastyquant-data:/work/data \
      -v /home/crussell/tastyquant-data/env/.env:/work/.env:ro \
      -e TQ_ENV_FILE=/work/.env -e TZ=UTC -w /work \
      10.10.0.6:5000/tastyquant/app:main \
      node apps/fetcher/dist/${cli}'';
  oneshot = cli: desc: {
    description = desc;
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = 900;
      ExecStart = imageRun cli;
    };
  };
in {
  age.secrets.tastyquant-env = {
    file = ../../secrets/tastyquant-env.age;
    mode = "0400";
    owner = "crussell";
    group = "users";
  };

  # Materialize the env files the repo's tooling expects at its root.
  systemd.services.tastyquant-env-deploy = {
    description = "tastyquant env files from agenix";
    after = [ "age-secret-tastyquant-env.service" ];
    wants = [ "age-secret-tastyquant-env.service" ];
    wantedBy = [ "multi-user.target" ];
    # The script shells out to awk — unit-script PATH is minimal, gawk
    # must be declared (its absence is why both earlier env writes
    # silently produced empty files / failed the switch).
    path = [ pkgs.gawk ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -eu
      awk_extract() { # $1=marker $2=dest — write via temp file (a bare
        # /dev/stdin pipe into install proved fragile on first deploy)
        awk -v m="$1" '
          $0 == "#--- " m " ---" { insec = 1; next }
          /^#--- / { insec = 0; next }
          insec && /^[A-Z]/ { print }
        ' ${config.age.secrets.tastyquant-env.path} > "$2.tmp"
        chown crussell:users "$2.tmp"
        chmod 0600 "$2.tmp"
        mv -f "$2.tmp" "$2"
      }
      mkdir -p /home/crussell/tastyquant-data/env
      awk_extract .env /home/crussell/tastyquant-data/env/.env
      awk_extract .env.production /home/crussell/tastyquant-data/env/.env.production
      # zai-api-key.age is an ENV FILE (ZHIPU_API_KEY=<key>), not a bare
      # key — strip the name or the desk sends "ZHIPU_API_KEY=<key>" as
      # the bearer token (401 Authentication Failed, 2026-10-23).
      printf 'NINEROUTER_API_KEY=%s\n' \
        "$(sed -n 's/^ZHIPU_API_KEY=//p' ${config.age.secrets.zai-api-key.path})" \
        > /home/crussell/tastyquant-data/env/.env.desk
      chown crussell:users /home/crussell/tastyquant-data/env/.env.desk
      chmod 0600 /home/crussell/tastyquant-data/env/.env.desk
    '';
  };

  # The four SERVING units are QUADLETS now (tastyquant-quadlets/*.container,
  # running the CI-built zot image :main) â deployed below. The
  # scan/capture/sweep oneshots still run tools/tq against the checkout
  # until the final checkout-removal step converts them too.
  systemd.user.services = {
    tastyquant-scan = oneshot "scan-cli.js"
      "tastyquant morning scan + repair pass (deterministic tickets; image-run)";
    tastyquant-capture =
      oneshot "capture-cli.js" "tastyquant daily read-only capture (image-run)";
    tastyquant-sweep = oneshot "sweep-cli.js"
      "tastyquant OCC-universe market-metrics sweep (read-only; image-run)";
  };

  # Serving quadlets (zot image): materialize read-only under /etc,
  # symlink into crussell's user quadlet search path, reload the user
  # manager (mechanics as sweatshop.nix D-017).
  environment.etc."tastyquant-quadlets/tastyquant-desk.container" = {
    source = ./tastyquant-quadlets/tastyquant-desk.container;
    mode = "0644";
  };
  environment.etc."tastyquant-quadlets/tastyquant-market.container" = {
    source = ./tastyquant-quadlets/tastyquant-market.container;
    mode = "0644";
  };
  environment.etc."tastyquant-quadlets/tastyquant-gateway.container" = {
    source = ./tastyquant-quadlets/tastyquant-gateway.container;
    mode = "0644";
  };
  environment.etc."tastyquant-quadlets/tastyquant-site.container" = {
    source = ./tastyquant-quadlets/tastyquant-site.container;
    mode = "0644";
  };
  system.activationScripts.tastyquant-quadlets = lib.stringAfter [ "users" ] ''
    dest=/home/crussell/.config/containers/systemd
    mkdir -p "$dest"
    for u in tastyquant-desk tastyquant-market tastyquant-gateway tastyquant-site; do
      ln -sfn "/etc/tastyquant-quadlets/$u.container" "$dest/$u.container"
      chown -h crussell:users "$dest/$u.container"
    done
    # clear containers left by the retired tools/tq units (same names)
    runuser -l crussell -- env XDG_RUNTIME_DIR=/run/user/1000 podman rm -f \
      tq-desk tq-market tq-gateway tq-site >/dev/null 2>&1 || true
    # stale enablement symlinks from the pre-quadlet nix units shadow the
    # generator (highest-precedence path, pointing into dead store paths) —
    # remove and restart, or a switched-out unit definition never applies
    # (2026-10-29 lesson: desk/market/gateway restarted as old node:22
    # builds until these were cleared)
    u=/home/crussell/.config/systemd/user
    rm -f "$u"/tastyquant-{desk,market,gateway,site}.service \
          "$u"/default.target.wants/tastyquant-{desk,market,gateway,site}.service
    /run/wrappers/bin/sudo systemctl --machine=crussell@.host --user daemon-reload || true
    /run/wrappers/bin/sudo systemctl --machine=crussell@.host --user restart \
      tastyquant-desk.service tastyquant-market.service \
      tastyquant-gateway.service tastyquant-site.service >/dev/null 2>&1 || true
  '';

  # zot (bees, Nebula-only) serves plain HTTP â mark it insecure so
  # the rootless quadlet pulls and podman auto-update work without
  # per-command tls flags.
  virtualisation.containers.registries.insecure = [ "10.10.0.6:5000" ];

  systemd.user.timers = {
    tastyquant-scan = {
      description = "tastyquant morning scan (weekdays 10:15 ET)";
      unitConfig.ConditionUser = "crussell";
      timerConfig = {
        OnCalendar = "Mon..Fri 10:15 America/New_York";
        Persistent = true;
      };
      wantedBy = [ "timers.target" ];
    };
    tastyquant-capture = {
      description = "tastyquant daily capture (weekdays 17:10 ET)";
      unitConfig.ConditionUser = "crussell";
      timerConfig = {
        OnCalendar = "Mon..Fri 17:10 America/New_York";
        Persistent = true;
      };
      wantedBy = [ "timers.target" ];
    };
    tastyquant-sweep = {
      description = "tastyquant nightly metrics sweep (weekdays 17:35 ET)";
      unitConfig.ConditionUser = "crussell";
      timerConfig = {
        OnCalendar = "Mon..Fri 17:35 America/New_York";
        Persistent = true;
      };
      wantedBy = [ "timers.target" ];
    };
  };
}
