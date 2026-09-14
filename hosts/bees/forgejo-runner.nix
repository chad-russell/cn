# Forgejo Actions runner on bees — `nix-host` label for real nix work.
#
# Second runner in the fleet (bee runs ubuntu-latest:host, see
# hosts/bee/forgejo-runner.nix). bees is the big iron (16C/32T, 62 GB,
# deploy origin), so it gets the `nix-host` label for CI that needs real
# nix evaluation/builds. Host-exec backend — docker-label runners cannot
# do nix closures sanely; no docker labels for nix build jobs.
#
# nix works for the job user without extra grants (daemon socket is
# 0666, allowed-users = *, flakes enabled system-wide, and /nix/store
# is readable); pinned flake inputs are already in bees's store.
# Registration token (TOKEN=... env file) agenix'd; the module's
# ExecStartPre re-registers automatically when token or labels change.
{ config, lib, pkgs, ... }:

{
  # Module default package is the ancient gitea-actions-runner 1.0.3;
  # forgejo-runner 13.x pairs with the Forgejo 15.x server on gateway.
  services.gitea-actions-runner.package = pkgs.forgejo-runner;

  services.gitea-actions-runner.instances.bees = {
    enable = true;
    name = "bees";
    url = "https://git.crussell.io";
    tokenFile = config.age.secrets.forgejo-runner-token-bees.path;
    labels = [ "nix-host:host" ];
    # Module defaults (bash … wget) + nix. hostPackages become the unit
    # PATH for :host jobs — the job shell sees exactly these (+ actions
    # tooling), NOT bees's systemPackages, so keep the list explicit.
    # Deploy jobs (deploy.yml) additionally need ssh/sudo/nixos-rebuild/
    # systemd-run.
    hostPackages = with pkgs; [
      bash
      coreutils
      curl
      gawk
      gitMinimal
      gnused
      nodejs
      wget
      nix
      openssh
      sudo
      nixos-rebuild
      systemd # systemd-run (detached bees self-switch in deploy.yml)
    ];
    settings = { log.level = "info"; };
  };

  age.secrets.forgejo-runner-token-bees.file =
    ../../secrets/forgejo-runner-token-bees.age;

  # CI deploys (deploy.yml) run the daemon and its :host job shells as
  # crussell — the module default DynamicUser can build but has no SSH
  # keys or sudo for `nix run .#deploy`. Registration + config stay under
  # /var/lib/gitea-runner/bees (absolute paths via $STATE_DIRECTORY and
  # --config), so repointing HOME is safe: job shells resolve ~/.ssh and
  # gitconfig as crussell. Trust note: single-user forge (registration
  # disabled) — only chad/glen can open PRs that execute jobs here.
  systemd.services."gitea-runner-bees" = {
    serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = lib.mkForce "crussell";
      Group = lib.mkForce "users";
    };
    environment.HOME = lib.mkForce "/home/crussell";
  };
}
