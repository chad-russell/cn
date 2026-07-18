# ── Host metadata: single source of truth ───────────────────────────
#
# Addressing + deploy info for every host. Consumed by:
#   - flake.nix               deploy/install scripts (the deployable hosts)
#   - modules/nebula-hosts.nix   /etc/hosts overlay entries (all hosts)
#
# Adding a host: add one entry here. If it's a NixOS deploy target, also give
# it `lan`, `deployUser`, `installUser` and a `nixosConfigurations.<name>`
# block in flake.nix. The deploy/install case statements and /etc/hosts then
# update automatically — no other edits needed.
#
# `hostsName` (optional) overrides the name written to /etc/hosts; it defaults
# to the attribute key.

{
  # ── NixOS deploy targets ──────────────────────────────────────────
  bee = {
    nebula = "10.10.0.12";
    lan = "192.168.20.105";
    deployUser = "crussell";
    installUser = "crussell";
  };
  bees = {
    nebula = "10.10.0.6";
    lan = "192.168.20.41";
    deployUser = "crussell";
    installUser = "crussell";
  };
  nas = {
    nebula = "10.10.0.3";
    lan = "192.168.20.31";
    deployUser = "crussell";
    installUser = "root";
  };
  gateway = {
    nebula = "10.10.0.2";
    lan = "178.156.171.212";
    deployUser = "root";
    installUser = "root";
    # The lighthouse role is historically named `nebula-hetzner` in /etc/hosts.
    hostsName = "nebula-hetzner";
  };

  # ── Overlay-only hosts (resolved via /etc/hosts, not deployed) ─────
  nebula-lh = { nebula = "10.10.0.1"; }; # local lighthouse on bee
  phone = { nebula = "10.10.0.11"; };
  think = { nebula = "10.10.0.10"; };
  homeassistant = { nebula = "10.10.0.51"; };
}
