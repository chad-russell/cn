# ── buzz-acp: server-side Buzz agents (glen + gloo lanes) ──────────────
#
# Each persona runs a buzz-acp harness (github.com/block/buzz, ACP sidecar
# extracted from the desktop AppImage — see /var/lib/dsh/buzz-acp/) that
# holds the persona's nostr nsec, subscribes to @-mentions on every relay
# channel at wss://buzz.internal.crussell.io, and spawns
# `dsh --profile acp-<lane>` as its ACP agent:
#
#   buzz-acp@glen → profiles/acp-glen (zai-coding/glm-5.3 — personal lane)
#   buzz-acp@gloo → profiles/acp-gloo (gloo/sonnet-4.6 — employer lane, WORK)
#
# Both profiles carry the persona prefix, the shared @glen/memory log
# (persona-scoped view), and their persona skill root — one DSH_HOME.
# Policy (Chad, 2026-09-14): thread-scoped sessions, mention-only routing,
# respond-to anyone (closed-membership relay). This replaced the custom
# @glen/channel-buzz dsh plugin entirely.
#
# Restart semantics follow the buzz remote-agents spec (I5): intentional
# termination must stay down — buzz-acp exits 0 on owner !shutdown and on
# the inactivity reap, so Restart=on-failure (never Restart=always).
# Per-instance launchers (run-glen.sh / run-gloo.sh, tracked in the
# /var/lib/dsh git repo) map agenix env to the harness env; no secret ever
# appears on a command line.

{ config, lib, ... }:

{
  systemd.services."buzz-acp@" = {
    description = "Buzz agent harness (%i lane)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "simple";
      User = "crussell";
      Group = "users";
      WorkingDirectory = "/home/crussell";
      ExecStart = "/var/lib/dsh/buzz-acp/run-%i.sh";
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

  systemd.services."buzz-acp@glen" = {
    wantedBy = [ "multi-user.target" ];
  };
  systemd.services."buzz-acp@gloo" = {
    wantedBy = [ "multi-user.target" ];
  };
}
