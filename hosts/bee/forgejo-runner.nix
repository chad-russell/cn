# Forgejo Actions runner on bee — executes CI jobs from git.crussell.io
# (Forgejo on gateway, see hosts/gateway/forgejo.nix).
#
# MVP: single instance, host-exec backend ("ubuntu-latest:host") — jobs run
# directly on bee, no container runtime involved. bee is podman-only (no
# docker daemon) and the smoke workflow is plain `run:` shell steps, so the
# module's default hostPackages (bash, coreutils, curl, git, nodejs, wget)
# cover it. Revisit container labels if/when jobs need isolation.
#
# Registration token generated on gateway via
#   forgejo actions generate-runner-token
# (as the forgejo user through systemd-run) and agenix'd as an env file
# exposing TOKEN=. The module reads it via systemd EnvironmentFile and
# re-registers automatically when the token or labels change
# (ExecStartPre compares .token-hash / .labels in the state dir).
{
  config,
  pkgs,
  ...
}:

{
  # Module default package is the ancient gitea-actions-runner 1.0.3;
  # forgejo-runner 13.x pairs with the Forgejo 15.x server on gateway.
  services.gitea-actions-runner.package = pkgs.forgejo-runner;

  services.gitea-actions-runner.instances.bee = {
    enable = true;
    name = "bee";
    url = "https://git.crussell.io";
    tokenFile = config.age.secrets.forgejo-runner-token.path;
    labels = [ "ubuntu-latest:host" ];
    settings = {
      log.level = "info";
    };
  };

  age.secrets.forgejo-runner-token.file = ../../secrets/forgejo-runner-token.age;
}
