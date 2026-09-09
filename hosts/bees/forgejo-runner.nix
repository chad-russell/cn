# Forgejo Actions runner on bees — `nix-host` label for real nix work.
#
# Second runner in the fleet (bee runs ubuntu-latest:host, see
# hosts/bee/forgejo-runner.nix). bees is the big iron (16C/32T, 62 GB,
# deploy origin), so it gets the `nix-host` label for CI that needs real
# nix evaluation/builds. Host-exec backend — docker-label runners cannot
# do nix closures sanely; no docker labels for nix build jobs.
#
# nix works from the module's DynamicUser without any extra grants:
#   - /nix/var/nix/daemon-socket/socket is 0666 (world-writable)
#   - /etc/nix/nix.conf: allowed-users = *, flakes enabled system-wide
#   - the module sets no ProtectSystem/PrivateTmp, so /nix/store (0755)
#     is readable; pinned flake inputs are already in bees's store
# Registration token (TOKEN=... env file) agenix'd; the module's
# ExecStartPre re-registers automatically when token or labels change.
{
  config,
  pkgs,
  ...
}:

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
    ];
    settings = {
      log.level = "info";
    };
  };

  age.secrets.forgejo-runner-token-bees.file = ../../secrets/forgejo-runner-token-bees.age;
}
