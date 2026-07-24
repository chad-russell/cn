# ── Hermes Agent (Nous Research) — Podman Quadlet on bee ────────────
#
# Long-running AI agent in gateway mode. Talks to Telegram (@wavydave_bot),
# exposes an OpenAI-compatible API on :8642 and a web dashboard on :9119 —
# both bound to the Nebula IP only (10.10.0.12).
#
# All secrets live in secrets/hermes-env.age (agenix). State lives in
# /var/lib/hermes (bind-mounted to /opt/data inside the container, owned by
# crussell via PUID/PGID=1000 so files are host-editable).
#
# Docs: https://hermes-agent.nousresearch.com/docs/user-guide/docker

{ config, lib, pkgs, ... }:

{
  age.secrets.hermes-env.file = ../../secrets/hermes-env.age;
  # ZAI_API_KEY — shared with opencode; let the hermes gateway use Z.AI models.
  age.secrets.zai-api-key.file = ../../secrets/zai-api-key.age;

  environment.etc."containers/systemd/hermes.container" = {
    source = ./hermes.container;
    mode = "0644";
  };

  # Data dir. The container's s6 init chowns it to PUID:PGID=1000 on first
  # boot, so we just need it to exist.
  system.activationScripts.hermes-dirs = lib.stringAfter [ "users" ] ''
    mkdir -p /var/lib/hermes
  '';
}
