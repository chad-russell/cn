# AI Server (bees)

AMD Strix Halo APU machine running llama.cpp for local LLM inference.

## Host Details

- **Hostname:** bees
- **LAN IP:** 192.168.20.41
- **Nebula IP:** 10.10.0.5
- **OS:** Fedora COSMIC Atomic 42
- **Hardware:** AMD Strix Halo APU (Radeon 8060S Graphics)

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      bees (192.168.20.41)                   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              llama-vulkan-radv toolbox              │    │
│  │  ┌──────────────────────────────────────────────┐   │    │
│  │  │  llama-swap (port 8000)                      │   │    │
│  │  │  - Dynamic model loading/swapping            │   │    │
│  │  │  - Proxies to llama-server instances         │   │    │
│  │  └──────────────────────────────────────────────┘   │    │
│  │                                                     │    │
│  │  llama-server (Vulkan/RADV backend)                 │    │
│  │  - Uses RADV (Mesa) Vulkan driver                   │    │
│  │  - AMD GFX1151 (Strix Halo)                         │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  Models: ~/.cache/llama.cpp/                                │
│  Config: ~/Code/config.yaml (Brunch-managed)                │
│  Service: systemd --user llama-swap.service                 │
└─────────────────────────────────────────────────────────────┘
```

## llama-swap

[llama-swap](https://github.com/mostlygeek/llama-swap) is a proxy server that dynamically loads/unloads models to conserve VRAM. It accepts OpenAI-compatible API requests on port 8000.

- **Listen:** 0.0.0.0:8000
- **Config:** `~/Code/config.yaml` (symlinked by `brunch apply ./config --target ai`)
- **Service:** `systemctl --user start llama-swap.service`
- **Definition:** `brunch/config/hosts/ai/index.bri`

### Config Format

```yaml
models:
  "model-id":
    name: "Display Name"
    cmd: /usr/bin/llama-server --port ${PORT} --host 127.0.0.1 -ngl 999 -m /path/to/model.gguf [options]
```

The `${PORT}` is dynamically assigned by llama-swap (starting from 10001).

## Model Management

### Storage Location

All models stored in: `/home/crussell/.cache/llama.cpp/`

### Downloading Models

llama-server can download directly from Hugging Face:

```bash
# Inside toolbox
toolbox run --container llama-vulkan-radv

# Download a model
llama-server --hf-repo unsloth/Qwen3.5-27B-GGUF:UD-Q8_K_XL --port 8080
```

Or use the config file with `-m` pointing to a HF repo URL pattern.

### Listing Cached Models

```bash
toolbox run --container llama-vulkan-radv llama-server --cache-list
```

### Deleting Models

```bash
rm ~/.cache/llama.cpp/unsloth_Qwen3-14B-*.gguf
```

## Toolbox Management

### List Toolboxes

```bash
toolbox list
```

### Enter Toolbox

```bash
toolbox enter llama-vulkan-radv
```

### Run Command in Toolbox

```bash
toolbox run --container llama-vulkan-radv <command>
```

## Current Models (as of 2026-02-28)

See `brunch/config/hosts/ai/index.bri`.

## Useful Commands

```bash
# Check GPU detection
toolbox run --container llama-vulkan-radv llama-server --help 2>&1 | grep -i vulkan

# Apply/update the AI host target
cd ~/Code/cn/brunch
brunch apply ./config --target ai

# Start llama-swap
systemctl --user start llama-swap.service

# Test API
curl http://localhost:8000/v1/models

# Check running llama-swap service
systemctl --user status llama-swap.service --no-pager
```

## Model Sources

- **unsloth** - GGUF quantizations: https://huggingface.co/unsloth
- **bartowski** - GGUF quantizations: https://huggingface.co/bartowski
- **Qwen official** - https://huggingface.co/Qwen

## Nebula Access

The server is accessible via Nebula mesh VPN at 10.10.0.5.

```bash
# SSH via Nebula
ssh crussell@10.10.0.5

# Access llama-swap API via Nebula
curl http://10.10.0.5:8000/v1/models
```
