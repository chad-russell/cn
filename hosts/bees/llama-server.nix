# ── llama.cpp Inference Server (Strix Halo) ──────────────────────
#
# On-demand local LLM serving via llama.cpp on the AMD Ryzen AI MAX+
# 395 iGPU (gfx1151 / Radeon 8060S). Uses the purpose-built
# strix-halo-toolboxes Vulkan (RADV) container — the most stable
# gfx1151 backend, rebuilt daily against llama.cpp master.
#
# GPU memory: 64 GB VRAM (BIOS-reserved) + 31 GB GTT aperture.
# No kernel-param changes needed — the BIOS reservation handles it.
#
# Usage:
#   sudo systemctl start llama-server@<model-name>
#   # model-name maps to /var/lib/llama/models/<model-name>.gguf
#   sudo systemctl stop llama-server@<model-name>
#   curl http://localhost:8888/v1/models   # check what's loaded
#
# The server exposes an OpenAI-compatible API at port 8888.
# Reachable over Nebula as http://10.10.0.6:8888
#
# Model download (run on bees):
#   hf download bartowski/L3.3-MS-Nevoria-70b-GGUF \
#     L3.3-MS-Nevoria-70b-Q4_K_M.gguf \
#     --local-dir /var/lib/llama/models

{ config, lib, pkgs, ... }:

let
  # Purpose-built Strix Halo (gfx1151) llama.cpp container.
  # Vulkan RADV — most stable and compatible backend for Strix Halo.
  llamaImage = "docker.io/kyuz0/amd-strix-halo-toolboxes:vulkan-radv";

  # Host port for the OpenAI-compatible API (Nebula: 10.10.0.6:8888)
  hostPort = 8888;

  # Context window (tokens). 64K meets Hermes Agent's minimum requirement
  # and is generous for story-writing. KV cache at Q8 uses ~10 GB VRAM.
  contextSize = 65536;

  # Wrapper: takes a model basename, runs the llama-server container.
  # The model file must exist at /var/lib/llama/models/<name>.gguf
  llama-run = pkgs.writeShellScriptBin "llama-run" ''
    set -euo pipefail
    MODEL="''${1:?usage: llama-run <model-name>}"
    exec ${pkgs.podman}/bin/podman run --rm \
      --name "llama-server-$MODEL" \
      --device /dev/dri \
      --group-add video --group-add render \
      --security-opt seccomp=unconfined \
      -p ${toString hostPort}:8080 \
      -v /var/lib/llama/models:/models:ro \
      ${llamaImage} \
      llama-server \
        -m "/models/$MODEL.gguf" \
        --host 0.0.0.0 --port 8080 \
        -c ${toString contextSize} \
        -ngl 999 \
        -fa 1 \
        --no-mmap \
        --cache-type-k q8_0 --cache-type-v q8_0 \
        --alias "$MODEL"
  '';
in
{
  # Model storage on local NVMe (1.7 TB free — never use NFS for model loading)
  system.activationScripts.llama-models-dir = lib.stringAfter [ "users" ] ''
    mkdir -p /var/lib/llama/models
  '';

  # HF Hub CLI for downloading GGUF models
  environment.systemPackages = [
    (pkgs.python3.withPackages (ps: [ ps.huggingface-hub ]))
  ];

  # Systemd template service: sudo systemctl start llama-server@<model-name>
  # %i resolves to the model basename (without .gguf extension).
  # On-demand only — not auto-started (no [Install] section).
  systemd.services."llama-server@" = {
    description = "llama.cpp inference server (model: %i)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "simple";
      # Clean up any stale container with the same name before starting
      ExecStartPre = "-${pkgs.podman}/bin/podman rm -f llama-server-%i";
      ExecStart = "${llama-run}/bin/llama-run %i";
      # Graceful stop: let llama-server finish in-flight requests
      ExecStop = "-${pkgs.podman}/bin/podman stop --time 30 llama-server-%i";
      TimeoutStartSec = 600; # image pull + model load can take minutes
      TimeoutStopSec = 60;
    };
  };
}
