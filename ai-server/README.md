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
│                      bees (192.168.20.41)                    │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              llama-vulkan-radv toolbox               │   │
│  │  ┌──────────────────────────────────────────────┐   │   │
│  │  │  llama-swap (port 8000)                       │   │   │
│  │  │  - Dynamic model loading/swapping             │   │   │
│  │  │  - Proxies to llama-server instances          │   │   │
│  │  └──────────────────────────────────────────────┘   │   │
│  │                                                      │   │
│  │  llama-server (Vulkan/RADV backend)                  │   │
│  │  - Uses RADV (Mesa) Vulkan driver                    │   │
│  │  - AMD GFX1151 (Strix Halo)                          │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  Models: ~/.cache/llama.cpp/                                │
│  Config: ~/Code/config.yaml                                 │
│  Start script: ~/Code/start-llama-swap.sh                   │
└─────────────────────────────────────────────────────────────┘
```

## llama-swap

[llama-swap](https://github.com/mostlygeek/llama-swap) is a proxy server that dynamically loads/unloads models to conserve VRAM. It accepts OpenAI-compatible API requests on port 8000.

- **Listen:** 0.0.0.0:8000
- **Config:** `~/Code/config.yaml`
- **Start:** `cd ~/Code && ./start-llama-swap.sh` (inside toolbox)

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

| Model ID | Name | Size | Quant |
|----------|------|------|-------|
| gpt-oss-120b | GPT-OSS 120B F16 | ~240GB | F16 |
| gpt-oss-20b | GPT-OSS 20B F16 | ~40GB | F16 |
| qwen3.5-35b-a3b | Qwen3.5-35B-A3B-UD-Q8_K_XL | ~35GB | UD-Q8_K_XL |
| qwen3.5-27b | Qwen3.5-27B-UD-Q8_K_XL | ~30GB | UD-Q8_K_XL |
| qwen3-4b-thinking | Qwen3-4B-Thinking-Q8_K_XL | ~5GB | Q8_K_XL |
| qwen3-4b-instruct | Qwen3-4B-Instruct-Q4_K_M | ~2.4GB | Q4_K_M |
| cydonia-24b | Cydonia-24B-Q6_K_L | ~20GB | Q6_K_L |
| dolphin-mistral | Dolphin Mistral 24B | ~48GB | BF16 |
| hermes-4 | Hermes-4.3-36B-Q8_0 | ~40GB | Q8_0 |
| glm-4.7-flash | GLM-4.7-Flash-Q8_K_XL | ~18GB | Q8_K_XL |
| nomic-embed-text-v2 | Nomic-Embed-Text-V2 | ~0.5GB | Q8_0 |

## Useful Commands

```bash
# Check GPU detection
toolbox run --container llama-vulkan-radv llama-server --help 2>&1 | grep -i vulkan

# Start llama-swap (in toolbox)
cd ~/Code && ./start-llama-swap.sh

# Test API
curl http://localhost:8000/v1/models

# Check running llama-swap process
ps aux | grep llama-swap
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
