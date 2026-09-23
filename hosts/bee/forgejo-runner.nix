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
{ config, pkgs, ... }:

{
  # Module default package is the ancient gitea-actions-runner 1.0.3;
  # forgejo-runner 13.x pairs with the Forgejo 15.x server on gateway.
  services.gitea-actions-runner.package = pkgs.forgejo-runner;

  services.gitea-actions-runner.instances.bee = {
    enable = true;
    name = "bee";
    url = "https://git.crussell.io";
    tokenFile = config.age.secrets.forgejo-runner-token.path;
    # seddit-rust: chad/seddit's CI (the sdt gates — containerized
    # cargo via the podman API socket). The job env points sdt at the
    # ROOTFUL socket (ci.yml: SDT_CONTAINER_HOST) and the unit's
    # supplementary group below grants socket access.
    labels = [ "seddit-rust:host" "ubuntu-latest:host" ];
    # podman + the sdt tooling: jobs drive containers through
    # /run/podman/podman.sock (0660 root:podman).
    hostPackages = with pkgs; [ bash coreutils curl gitMinimal nodejs wget podman ];
    settings = { log.level = "info"; };
  };

  # Socket access for the (DynamicUser) runner: the podman group owns
  # the rootful socket. SupplementaryGroups is the sanctioned shape for
  # shared groups on dynamic users (the primary Group must stay the
  # passwd one or rootless podman dies — nix gotcha).
  systemd.services.gitea-runner-bee.serviceConfig.SupplementaryGroups = [ "podman" ];

  age.secrets.forgejo-runner-token.file =
    ../../secrets/forgejo-runner-token.age;
}
