# ── gateway: bees off-box liveness watch → Discord ──────────────────
#
# Closes the 2026-09-08 gap: bees went dark ~4h with ZERO alerts because
# every alert path (ntfy, beszel hub, freshness checks) lived ON bees.
#
# Design (task t_43990729):
#   - Watcher runs on gateway — always-up, off-LAN vantage. bee shares
#     LAN+power with bees, so it is NOT an independent failure domain.
#   - Probe: ping bees' Nebula IP 10.10.0.6 every 2 min. Cheap, no creds,
#     no agent on bees. (Nebula loss also manifests as ping loss from
#     here — still an outage worth paging for.)
#   - Alert path: DIRECT to Discord #infra via webhook — does not depend
#     on bees (ntfy), bee (hermes), or the LAN. Deliberate, documented
#     exception to the "no secrets on the VPS" invariant (that invariant
#     was about TLS/CA/S3 creds; a revocable, low-value webhook is an
#     acceptable trade for an alert path that survives bees).
#   - 3 consecutive failures (~6 min) → alert once; re-fire every 30 min
#     while still down (no spam); all-clear with downtime duration on
#     recovery.
#   - State in /var/lib/bees-watch so a gateway reboot mid-outage does
#     not re-alert (bees is still down; recovery still reports).
#
# Drill (test without touching bees): the drill units probe a dead IP on
# the same cadence with a separate state file:
#   systemctl start bees-watch-drill@10.10.0.99.timer   # → alert ~7 min
#   systemctl stop bees-watch-drill@10.10.0.99.timer
#   systemctl start bees-watch-drill@10.10.0.6.timer    # → all-clear
#   systemctl stop 'bees-watch-drill@*' ... && rm /var/lib/bees-watch/drill*

{ config, lib, pkgs, ... }:

let
  # Probe script: bees-watch-probe <target-ip> [state-file]
  # Exit 0 always (a failed probe is DATA, not a unit failure); journal
  # lines tell the story. All binaries are explicit store paths.
  probe = pkgs.writeShellScript "bees-watch-probe" ''
    set -u
    target="''${1:-10.10.0.6}"
    state="''${2:-/var/lib/bees-watch/state}"
    now=$(${pkgs.coreutils}/bin/date +%s)

    fail_count=0   # consecutive failed probes
    first_fail=0   # epoch of first failure in the current streak
    last_alert=0   # epoch of the last Discord alert (0 = never alerted)
    if [ -f "$state" ]; then
      # shellcheck disable=SC1090
      . "$state" || true
    fi

    send() { # $1 = message text
      if ${pkgs.curl}/bin/curl -fsS --max-time 15 -X POST \
          -H 'Content-Type: application/json' \
          --data-binary "$(${pkgs.jq}/bin/jq -cn --arg c "$1" '{content: $c}')" \
          "$DISCORD_WEBHOOK_URL" >/dev/null 2>&1; then
        echo "sent: $1"
      else
        echo "WARN: Discord webhook POST failed"
      fi
    }

    save() { # fail_count first_fail last_alert
      umask 027
      printf 'fail_count=%s\nfirst_fail=%s\nlast_alert=%s\n' "$1" "$2" "$3" \
        > "$state.tmp" && ${pkgs.coreutils}/bin/mv "$state.tmp" "$state"
    }

    dur() { # seconds → "1h 23m"
      printf '%dh %02dm' $(( $1 / 3600 )) $(( ($1 % 3600) / 60 ))
    }

    if ${pkgs.iputils}/bin/ping -c 2 -W 2 "$target" >/dev/null 2>&1; then
      if [ "$last_alert" -gt 0 ]; then
        send "✅ bees-watch: bees ($target) is back UP — was unreachable for $(dur $((now - first_fail)))"
        save 0 0 0
      elif [ "$fail_count" -gt 0 ]; then
        echo "recovered before alerting (streak was $fail_count)"
        save 0 0 0
      else
        echo "ok: $target reachable"
      fi
      exit 0
    fi

    if [ "$fail_count" -eq 0 ]; then
      first_fail=$now
    fi
    fail_count=$(( fail_count + 1 ))

    if [ "$fail_count" -ge 3 ]; then
      if [ "$last_alert" -eq 0 ]; then
        send "🚨 bees-watch: bees ($target) UNREACHABLE from gateway — 3 consecutive probes failed (~6 min)"
        last_alert=$now
      elif [ $(( now - last_alert )) -ge 1800 ]; then
        send "🚨 bees-watch: bees ($target) still unreachable — down $(dur $((now - first_fail))) (re-alert, next in 30m)"
        last_alert=$now
      else
        echo "still down (fail streak $fail_count), within 30m re-alert window"
      fi
    else
      echo "probe FAILED $fail_count/3 at $(${pkgs.coreutils}/bin/date -Is)"
    fi
    save "$fail_count" "$first_fail" "$last_alert"
  '';
in {
  users.users.bees-watch = {
    isSystemUser = true;
    group = "bees-watch";
    useDefaultShell = true;
    description = "bees off-box liveness watcher";
  };
  users.groups.bees-watch = { };

  age.secrets.discord-infra-webhook = {
    # Contains: DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/<id>/<token>
    # Webhook "bees-watch alerts" in the #infra channel, created 2026-09-09
    # by hermes-glen. Revoke/rotate by recreating the webhook and
    # re-encrypting this file.
    file = ../../secrets/discord-infra-webhook.age;
    owner = "bees-watch";
    group = "bees-watch";
  };

  systemd.services.bees-watch = {
    description = "bees liveness probe (ping) with Discord alerting";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    # If the watcher itself breaks (config/env error), ntfy (on bees —
    # reachable whenever the watcher is broken-but-bees-up) says so.
    onFailure = [ "ntfy-failure@bees-watch.service" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${probe} 10.10.0.6";
      User = "bees-watch";
      Group = "bees-watch";
      StateDirectory = "bees-watch";
      StateDirectoryMode = "0750";
      EnvironmentFile = config.age.secrets.discord-infra-webhook.path;
      # Unprivileged ping sockets (no CAP_NET_RAW needed on NixOS).
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
    };
  };

  systemd.timers.bees-watch = {
    description = "bees liveness probe every 2 min";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "2min";
      AccuracySec = "30s";
      Unit = "bees-watch.service";
    };
  };

  # ── Drill template: identical probe, dead target, separate state ──
  systemd.services."bees-watch-drill@" = {
    description = "bees-watch drill: probe %i instead of bees";
    serviceConfig = {
      Type = "oneshot";
      # %i (instance = target IP) expands in ExecStart.
      ExecStart = "${probe} %i /var/lib/bees-watch/drill";
      User = "bees-watch";
      Group = "bees-watch";
      EnvironmentFile = config.age.secrets.discord-infra-webhook.path;
    };
  };

  systemd.timers."bees-watch-drill@" = {
    description = "bees-watch drill cadence every 2 min";
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "2min";
      AccuracySec = "30s";
      Unit = "bees-watch-drill@%i.service";
    };
  };
}
