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
  tq = "${repo}/tools/tq";
  execEnv = {
    PATH = "/run/current-system/sw/bin:/usr/bin:/bin";
    HOME = "/home/crussell";
  };
  # Serve-unit template: oneshot launcher with matching --stop. Gates on
  # the env file (the env-deploy system unit can't order against user
  # units — the condition makes the dependency fail-safe instead).
  serve = name: desc: {
    description = desc;
    after = [ "podman.socket" "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "default.target" ];
    unitConfig.ConditionPathExists = "${repo}/.env";
    environment = execEnv;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      WorkingDirectory = repo;
      TimeoutStartSec = 1200;
      ExecStart = "${tq} ${name}";
      ExecStop = "${tq} ${name} --stop";
    };
  };
  oneshot = name: desc: {
    description = desc;
    environment = execEnv;
    serviceConfig = {
      Type = "oneshot";
      WorkingDirectory = repo;
      TimeoutStartSec = 600;
      ExecStart = "${tq} ${name}";
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
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      split() { # $1=marker $2=dest
        awk -v m="$1" '
          $0 == "#--- " m " ---" { insec = 1; next }
          /^#--- / { insec = 0; next }
          insec && /^[A-Z]/ { print }
        ' ${config.age.secrets.tastyquant-env.path} \
          | install -o crussell -g users -m 0600 /dev/stdin "$2"
      }
      split .env ${repo}/.env
      split .env.production ${repo}/.env.production
      printf 'NINEROUTER_API_KEY=%s\n' \
        "$(cat ${config.age.secrets.zai-api-key.path})" \
        > ${repo}/.env.desk
      chown crussell:users ${repo}/.env.desk
      chmod 0600 ${repo}/.env.desk
    '';
  };

  systemd.user.services = {
    tastyquant-gateway = serve "gateway"
      "tastyquant order gateway (tools/tq gateway)";
    tastyquant-market = serve "market"
      "tastyquant market service (tools/tq market)";
    tastyquant-desk = serve "desk"
      "tastyquant chat desk (apps/desk Next.js on 10.10.0.12:3320 → trades.internal)";
    tastyquant-scan = oneshot "scan" "tastyquant morning scan + repair pass (deterministic tickets)";
    tastyquant-capture = oneshot "capture" "tastyquant daily read-only capture";
    tastyquant-sweep = oneshot "sweep" "tastyquant OCC-universe market-metrics sweep (read-only)";
  };

  # Direct-to-Z.AI (9router decommissioned 2026-10-23).
  systemd.user.services.tastyquant-desk.environment =
    execEnv // { TQ_LLM_BASE_URL = "https://api.z.ai/api/coding/paas/v4"; };

  systemd.user.timers = {
    tastyquant-scan = {
      description = "tastyquant morning scan (weekdays 10:15 ET)";
      timerConfig = {
        OnCalendar = "Mon..Fri 10:15 America/New_York";
        Persistent = true;
      };
      wantedBy = [ "timers.target" ];
    };
    tastyquant-capture = {
      description = "tastyquant daily capture (weekdays 17:10 ET)";
      timerConfig = {
        OnCalendar = "Mon..Fri 17:10 America/New_York";
        Persistent = true;
      };
      wantedBy = [ "timers.target" ];
    };
    tastyquant-sweep = {
      description = "tastyquant nightly metrics sweep (weekdays 17:35 ET)";
      timerConfig = {
        OnCalendar = "Mon..Fri 17:35 America/New_York";
        Persistent = true;
      };
      wantedBy = [ "timers.target" ];
    };
  };
}
