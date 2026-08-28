# ── ComfyUI Image/Video Generation (Strix Halo) ──────────────────
#
# On-demand image/video generation via ComfyUI on the AMD Ryzen AI
# MAX+ 395 iGPU (gfx1151 / Radeon 8060S). Uses kyuz0's purpose-built
# strix-halo-comfyui toolbox container: Fedora + TheRock ROCm 7
# nightlies (PyTorch scoped to gfx1151), ComfyUI at /opt/ComfyUI,
# pre-validated Strix Halo workflows and custom nodes baked in.
#
# GPU memory: 64 GB VRAM (BIOS-reserved) + 31 GB GTT aperture.
# No kernel-param changes needed — same conclusion as llama-server.
# NOTE: don't run simultaneously with llama-server@* — Qwen Image
# fp8 (~40 GB) plus a 27B LLM will not both fit in VRAM.
#
# Usage:
#   sudo systemctl start comfyui          # on-demand, not auto-started
#   sudo systemctl stop comfyui           # frees VRAM immediately
#   # UI + API on http://10.10.0.6:8188 (Nebula), keyless like :8888
#
# Model downloads (run while the service is up):
#   sudo podman exec -it comfyui model_manager      # TUI, per-workflow
#   sudo podman exec -it comfyui /opt/get_qwen_image.sh 1   # CLI, script per family
# Models land in /var/lib/llama-style local NVMe at /var/lib/comfyui/models
# (HOME inside the container is /models, so the toolbox scripts'
# ~/comfy-models layout maps onto the persistent mount).
#
# Sibling module: hosts/bees/llama-server.nix (same wrapper pattern).
{ config, lib, pkgs, ... }:

let
  # Purpose-built Strix Halo (gfx1151) ComfyUI toolbox, ROCm (TheRock).
  # `latest` is the maintainer's verified-stable channel.
  comfyImage = "docker.io/kyuz0/amd-strix-halo-comfyui:latest";

  # Host port for the ComfyUI UI/API (Nebula: 10.10.0.6:8188)
  hostPort = 8188;

  # Persistent state on local NVMe (never NFS — model loading is IO/latency sensitive)
  dataDir = "/var/lib/comfyui";

  # Declarative replacement for the toolbox's /opt/set_extra_paths.sh:
  # points ComfyUI at the persistent model tree. Base path matches the
  # toolbox scripts' $HOME/comfy-models layout with HOME=/models.
  extraModelPaths = pkgs.writeText "extra_model_paths.yaml" ''
    comfyui:
        base_path: /models/comfy-models

        text_encoders: text_encoders
        vae: vae
        checkpoints: checkpoints
        diffusion_models: diffusion_models
        unet: unet
        loras: loras
        latent_upscale_models: latent_upscale_models
        clip_vision: clip_vision
  '';

  # Wrapper: runs the ComfyUI container with the maintainer's validated
  # Strix Halo flags (from his start_comfy_ui alias):
  #   --bf16-vae          prevents OOM during VAE decode
  #   --disable-mmap      critical on gfx1151: mmap >64 GB is slow (ROCm bug)
  #   --cache-none        aggressive unified-memory (GTT vs RAM) management
  #   --gpu-only / --disable-smart-memory  keep tensors on GPU, no CPU offload shuffling
  # TORCH_* env vars replicate his /etc/profile.d/01-rocm-envs.sh, which
  # only loads for interactive shells — headless runs must set it explicitly.
  comfy-run = pkgs.writeShellScriptBin "comfy-run" ''
    set -euo pipefail
    exec ${pkgs.podman}/bin/podman run --rm \
      --name comfyui \
      --device /dev/dri --device /dev/kfd \
      --group-add video --group-add render \
      --security-opt seccomp=unconfined \
      -p ${toString hostPort}:8188 \
      -e TORCH_ROCM_AOTRITON_ENABLE_EXPERIMENTAL=1 \
      -e TORCH_BLAS_PREFER_HIPBLASLT=1 \
      -e HOME=/models \
      -v ${dataDir}/models:/models \
      -v ${dataDir}/outputs:/opt/ComfyUI/output \
      -v ${dataDir}/input:/opt/ComfyUI/input \
      -v comfyui-user:/opt/ComfyUI/user \
      -v ${extraModelPaths}:/opt/ComfyUI/extra_model_paths.yaml:ro \
      --workdir /opt/ComfyUI \
      ${comfyImage} \
      /opt/venv/bin/python main.py \
        --listen 0.0.0.0 --port 8188 \
        --disable-mmap --gpu-only --disable-smart-memory \
        --cache-none --bf16-vae
  '';
in {
  # Persistent dirs on local NVMe. Non-recursive chown keeps the tree
  # user-browsable (container writes as root; world-readable anyway).
  system.activationScripts.comfyui-dirs = lib.stringAfter [ "users" ] ''
    mkdir -p ${dataDir}/models/comfy-models/{text_encoders,vae,checkpoints,diffusion_models,unet,loras,latent_upscale_models,clip_vision}
    mkdir -p ${dataDir}/outputs ${dataDir}/input
    chown crussell:users ${dataDir} ${dataDir}/models ${dataDir}/models/comfy-models ${dataDir}/models/comfy-models/* ${dataDir}/outputs ${dataDir}/input
  '';

  # On-demand systemd service — no [Install] section, not auto-started.
  # Toggle with: sudo systemctl start/stop comfyui
  systemd.services.comfyui = {
    description = "ComfyUI image/video generation (Strix Halo ROCm)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "simple";
      # Clean up any stale container with the same name before starting
      ExecStartPre = "-${pkgs.podman}/bin/podman rm -f comfyui";
      ExecStart = "${comfy-run}/bin/comfy-run";
      # Graceful stop attempt; ComfyUI ignores SIGTERM until podman escalates
      # to SIGKILL — `podman run` then exits with propagated code 137. Treat
      # 137 (and signal deaths) as success so a normal stop doesn't land in
      # `systemctl --failed`.
      ExecStop = "-${pkgs.podman}/bin/podman stop --time 30 comfyui";
      SuccessExitStatus = [ "SIGTERM" "SIGKILL" 137 ];
      TimeoutStartSec = 1800; # first start pulls a ~5.4 GB image
      TimeoutStopSec = 90;
    };
  };
}
