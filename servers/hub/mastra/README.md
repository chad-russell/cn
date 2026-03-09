# Mastra on Hub

This directory contains the Mastra server project hosted on `hub`.

## Endpoints

- Studio: `https://mastra.internal.crussell.io`
- Health: `https://mastra.internal.crussell.io/health`
- OpenAPI: `https://mastra.internal.crussell.io/openapi.json`
- Swagger: `https://mastra.internal.crussell.io/swagger-ui`

## Runtime

- Container port: `4111`
- Host port: `30411`
- Quadlet: `../quadlets/containers/mastra.container`
- Persistent storage: `/srv/mastra/data/mastra.db`

## Local Development

```bash
cd servers/hub/mastra
npm install
npm run dev
```

## Build Container Image

```bash
cd servers/hub/mastra
podman build -t localhost/mastra:latest -f Containerfile .
```

## Deploy on Hub

```bash
cp servers/hub/quadlets/containers/mastra.container ~/.config/containers/systemd/
systemctl --user daemon-reload
systemctl --user start mastra
```

## LLM Configuration

The default model uses your local llama-swap server:

- `OPENAI_BASE_URL=http://192.168.20.41:8000/v1`
- `OPENAI_API_KEY=local-llama`
- `MASTRA_MODEL=qwen3.5-9b`

Change `MASTRA_MODEL` in the quadlet to any model id your llama-swap endpoint serves.
