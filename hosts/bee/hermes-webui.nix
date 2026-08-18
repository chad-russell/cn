# ── Hermes WebUI on bee ────────────────────────────────────────────
#
# Community web frontend for Hermes Agent (github.com/nesquena/hermes-webui).
# Served at https://hermes.internal.crussell.io — bees Caddy terminates TLS
# (wildcard *.internal.crussell.io cert) and reverse-proxies to bee over the
# Nebula overlay (10.10.0.12:8787), the same pattern as hermes-serve.
#
# The WebUI runs the agent IN-PROCESS against the real HERMES_HOME
# (/var/lib/hermes/.hermes) — the same state the gateway
# (hermes-agent.service) and hermes-serve share. That gives the session
# sidebar, workspace browser, memory/skills/cron panels full fidelity with
# the agent Chad talks to on Telegram. The upstream module docs call out
# exactly this co-located deployment (run the service as the agent service
# account, never changing ownership of the shared hermesHome).
#
# Auth: WebUI's OWN password gate (HMAC cookie, /login page) — NOT Caddy
# basic_auth, which breaks the PWA service-worker update fetches. Secret
# lives in secrets/hermes-webui-env.age.

{ config, lib, pkgs, ... }:

{
  # WebUI login password (HERMES_WEBUI_PASSWORD). Separate from
  # hermes-bee-env so it can be rotated independently.
  age.secrets.hermes-webui-env.file = ../../secrets/hermes-webui-env.age;

  services.hermes-webui = {
    enable = true;

    # Nebula-overlay bind only — never LAN/public. bees Caddy (Network=host)
    # reaches this over Nebula; hermes.internal.crussell.io is the only door.
    host = "10.10.0.12";
    port = 8787;

    # Co-locate with the gateway: same user, same group, same state.
    # The module only creates its own user/group when left at defaults —
    # pointing at crussell/hermes reuses bee's existing accounts, matching
    # services.hermes-agent on this host.
    user = "crussell";
    group = "hermes";

    # The real agent state — shared with hermes-agent.service + hermes-serve.
    hermesHome = "/var/lib/hermes/.hermes";

    # WebUI's own sessions/attachments/settings live inside HERMES_HOME
    # (default $HERMES_HOME/webui) so bee's restic backup of /var/lib/hermes
    # covers them. Explicit here for clarity + survives module default drift.
    stateDir = "/var/lib/hermes/.hermes/webui";

    # Keep webui's agent interpreter in lockstep with the gateway: derive
    # HERMES_WEBUI_PYTHON from the pinned hermes-agent package the gateway
    # itself runs (services.hermes-agent.package default → passthru.hermesVenv).
    agent.package = config.services.hermes-agent.package;

    # Provider keys (ZAI/Gloo/OpenRouter/Telegram) for in-process agent runs,
    # plus HERMES_WEBUI_PASSWORD for the login gate. The module's
    # ExecStartPre guard rejects protected runtime keys here, which is what
    # we want (host/port/state are set via module options above).
    environmentFiles = [
      config.age.secrets.hermes-bee-env.path
      config.age.secrets.hermes-webui-env.path
    ];

    # Workspace browser roots at crussell's home (dev quadlet configs, tasty
    # scripts) rather than ~/workspace (unset on servers).
    extraEnvironment = {
      HERMES_WEBUI_DEFAULT_WORKSPACE = "/home/crussell";
      # Chat needs to reach the SearXNG search backend, same as the gateway.
      SEARXNG_URL = "http://127.0.0.1:8888";
      # Same chromium override the gateway uses for agent-browser.
      AGENT_BROWSER_EXECUTABLE_PATH = "${pkgs.chromium}/bin/chromium";
    };
  };

  # The upstream module emits its own tmpfiles rule for non-default
  # stateDirs (d stateDir 0700 user group), which creates
  # /var/lib/hermes/.hermes/webui as crussell:hermes on first boot.
}
