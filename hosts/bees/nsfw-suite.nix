# nsfw-suite — private image suite (nsfw.internal.crussell.io, 127.0.0.1:8097)
#
# Migrated 2026-10-16 from a hand-managed user unit
# (~/.config/systemd/user/nsfw-suite.service) after a two-week silent
# outage: that unit's ExecStart pointed at an un-rooted nix store python
# env that was garbage-collected, so every start died 203/EXEC while
# repo-based deploys and monitoring never saw it. Declaring the unit
# here pins the interpreter to pkgs.python3 inside the system closure
# (GC-proof) and puts the service on the normal deploy/monitoring path.
#
# The app itself is stdlib-only Python (no third-party packages) living
# outside this repo at ~/nsfw-suite/app/serve.py — deliberately not
# vendored, so it keeps its own update workflow. On-demand image
# generation shells out to `sudo systemctl start comfyui` (wheel
# NOPASSWD via base-server) and refuses to start ComfyUI while
# llama-server holds the GPU, so this unit must run as crussell with
# sudo rights intact (no NoNewPrivileges).
{ pkgs, ... }:

{
  systemd.services.nsfw-suite = {
    description =
      "nsfw-suite — private image suite (nsfw.internal.crussell.io)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    # Instant ntfy ping on unit failure (process layer of the
    # freshness-checks contract; the crash loop below predated this).
    onFailure = [ "ntfy-failure@nsfw-suite.service" ];

    serviceConfig = {
      User = "crussell";
      Group = "users";
      ExecStart =
        "${pkgs.python3}/bin/python3 /home/crussell/nsfw-suite/app/serve.py";
      WorkingDirectory = "/home/crussell/nsfw-suite";
      # env file (mode 600) holds OPENROUTER_API_KEY for image prompts
      EnvironmentFile = "/home/crussell/.config/nsfw-suite/env";
      Environment = [
        "NSFW_HOST=127.0.0.1"
        "NSFW_PORT=8097"
        "NSFW_DATA=/home/crussell/nsfw-suite-data"
      ];
      Restart = "on-failure";
      RestartSec = 3;
    };
  };

  # Output layer: the site must actually answer through Caddy hourly —
  # catches a dead backend, a bind failure, or a broken route even when
  # the unit looks healthy (the 2026-10 outage ran 13 days undetected).
  homelab.freshnessChecks.nsfw-suite = {
    description = "nsfw-suite site answers via Caddy";
    onCalendar = "hourly";
    checkCommand = ''
      msg="$(curl -fsS --max-time 10 -o /dev/null -w 'HTTP %{http_code}' https://nsfw.internal.crussell.io/ 2>&1)" \
        && echo "site answered: $msg" \
        || { echo "no answer: $msg"; exit 1; }
    '';
  };
}
