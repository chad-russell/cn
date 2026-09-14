# ── buzz-acp: server-side Buzz agents (glen + gloo lanes) ──────────────
#
# Each persona runs a buzz-acp harness (github.com/block/buzz, ACP sidecar
# extracted from the desktop AppImage — see /var/lib/dsh/buzz-acp/) that
# holds the persona's nostr nsec, subscribes to @-mentions on every relay
# channel at wss://buzz.internal.crussell.io, and spawns
# `dsh --profile acp-<lane>` as its ACP agent:
#
#   buzz-acp-glen.service → profiles/acp-glen (zai-coding/glm-5.3 — personal)
#   buzz-acp-gloo.service → profiles/acp-gloo (gloo/sonnet-4.6 — employer, WORK)
#
# Both profiles carry the persona prefix, the shared @glen/memory log
# (persona-scoped view), and their persona skill root — one DSH_HOME.
# Policy (Chad, 2026-09-14): thread-scoped sessions, mention-only routing,
# respond-to anyone (closed-membership relay). This replaced the custom
# @glen/channel-buzz dsh plugin entirely.
#
# CONCRETE units, not a template: defining systemd.services."buzz-acp@glen"
# (even wantedBy-only) makes NixOS emit a real instance unit file that
# SHADOWS the template with no ExecStart — systemd then refuses to start it
# ("Service has no ExecStart="), which is exactly what happened on the
# first deploy attempt (2026-09-13). A Nix function keeps them identical.
#
# Restart semantics follow the buzz remote-agents spec (I5): intentional
# termination must stay down — buzz-acp exits 0 on owner !shutdown and on
# the inactivity reap, so Restart=on-failure (never Restart=always).
# Launchers (run-<lane>.sh, tracked in the /var/lib/dsh git repo) map
# agenix env to the harness env; no secret ever appears on a command line.

{ config, lib, ... }:

let
  buzzAcp = lane: {
    description = "Buzz agent harness (${lane} lane)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      User = "crussell";
      Group = "users";
      WorkingDirectory = "/home/crussell";
      ExecStart = "/var/lib/dsh/buzz-acp/run-${lane}.sh";
      # Persona nsec (GLEN_BUZZ_NSEC_*) + provider keys — same agenix
      # sources as dsh-web (modules/dsh.nix); equal definitions merge.
      EnvironmentFile = [
        config.age.secrets.glen-buzz-nsecs.path
        config.age.secrets.zai-api-key.path
        config.age.secrets.gloo-api-key.path
      ];
      Restart = "on-failure";
      RestartSec = "10";
    };
    # The harness (and the dsh agent it spawns) resolves bash/bwrap/date
    # by bare name; the systemd default unit PATH has none of them.
    environment.PATH = lib.mkForce "/run/current-system/sw/bin";
  };
in {
  systemd.services.buzz-acp-glen = buzzAcp "glen";
  systemd.services.buzz-acp-gloo = buzzAcp "gloo";
}
