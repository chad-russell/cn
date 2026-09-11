# ── glen heartbeat driver (bee) ─────────────────────────────────────
#
# Self-contained host support for glen's caller-agnostic heartbeat
# tool (/home/crussell/glen/tools/heartbeat — see the glen repo's
# research/design/heartbeat-organ.md). One DUMB system timer execs the
# tool every minute; the tool owns everything else: jobs as data in
# glen's state/jobs.json, deterministic filters before any LLM turn,
# and its own headless dsh runs. This module knows nothing about jobs
# and is the module's entire reason to exist (invocation-agnostic
# tool, isolated host wiring — Chad's 2026-09-11 design call).
#
# Key: ZHIPU_API_KEY from the existing agenix zai-api-key (the tool
# skips its login-zsh fallback when the env var is present, so manual
# and scheduled invocations behave identically). PATH follows the
# modules/dsh.nix lesson: the systemd default PATH lacks node/dsh, so
# point at the system profile.

{ config, lib, pkgs, ... }:

{
  # Equal definition merges with modules/dsh.nix's (same .age source).
  age.secrets.zai-api-key.file = ../secrets/zai-api-key.age;

  systemd.services.glen-heartbeat = {
    description = "glen heartbeat dispatcher (jobs live in /home/crussell/glen)";
    serviceConfig = {
      Type = "oneshot";
      User = "crussell";
      Group = "users";
      WorkingDirectory = "/home/crussell/glen";
      ExecStart = "/home/crussell/glen/tools/heartbeat";
      # zai-api-key.age exports ZHIPU_API_KEY=…
      EnvironmentFile = [ config.age.secrets.zai-api-key.path ];
    };
    # node, dsh, bash, git live in the system profile (dsh.nix lesson;
    # mkForce because the systemd module sets a store-path default).
    environment.PATH = lib.mkForce "/run/current-system/sw/bin";
    environment.HOME = "/home/crussell";
  };

  systemd.timers.glen-heartbeat = {
    description = "drive glen's heartbeat tool every minute";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "3min";
      OnUnitActiveSec = "60s";
      AccuracySec = "15s";
      Unit = "glen-heartbeat.service";
    };
  };
}
