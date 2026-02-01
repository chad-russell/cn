# Kubernetes Manifests

This directory contains Kubernetes manifests for applications running on k3s HA cluster.

## Structure

- `longhorn/` - Longhorn distributed storage system
- `linkding/` - Linkding bookmark manager
- `open-webui/` - Open WebUI LLM interface
- `papra/` - Papra personal resource manager
- `searxng/` - SearXNG privacy-respecting metasearch engine
- `ntfy/` - Ntfy notification service
- `immich/` - Immich photo backup solution
- `openclaw/` - OpenClaw personal AI assistant (hybrid deployment)

## How it works

K3s has a built-in Helm controller that automatically applies HelmChart CRDs placed in `/var/lib/rancher/k3s/server/manifests/`.

To deploy applications:
1. Create a `HelmChart` resource in appropriate subdirectory
2. Apply it to the cluster: `kubectl apply -f k8s/<app>/`

K3s will automatically install and manage Helm release.

## NodePort Service Registry

Services exposed via NodePort are routed through Caddy reverse proxy using the cluster VIP (192.168.20.32).

| Service | Namespace | NodePort | Domain |
|---------|-----------|----------|--------|
| linkding | linkding | 30080  | linkding.internal.crussell.io |
| immich | immich | 30081  | photos.crussell.io |
| open-webui | open-webui | 30082  | openwebui.crussell.io |
| papra | papra | 30083  | papra.internal.crussell.io |
| searxng | searxng | 30084  | searxng.internal.crussell.io |
| ntfy | ntfy | 30085  | ntfy.crussell.io |
| openclaw | openclaw | 30086  | claw.internal.crussell.io |


## Structure

- `longhorn/` - Longhorn distributed storage system
- `linkding/` - Linkding bookmark manager
- `open-webui/` - Open WebUI LLM interface
- `papra/` - Papra personal resource manager
- `searxng/` - SearXNG privacy-respecting metasearch engine
- `ntfy/` - Ntfy notification service
- `immich/` - Immich photo backup solution

## How it works

K3s has a built-in Helm controller that automatically applies HelmChart CRDs placed in `/var/lib/rancher/k3s/server/manifests/`. 

To deploy applications:
1. Create a `HelmChart` resource in the appropriate subdirectory
2. Apply it to the cluster: `kubectl apply -f k8s/<app>/`

K3s will automatically install and manage the Helm release.

## NodePort Service Registry

Services exposed via NodePort are routed through Caddy reverse proxy using the cluster VIP (192.168.20.32).

| Service | Namespace | NodePort | Domain |
|---------|-----------|----------|--------|
| linkding | linkding | 30080  | linkding.internal.crussell.io |
| immich | immich | 30081  | photos.crussell.io |
| open-webui | open-webui | 30082  | openwebui.crussell.io |
| papra | papra | 30083  | papra.internal.crussell.io |
| searxng | searxng | 30084  | searxng.internal.crussell.io |
| ntfy | ntfy | 30085  | ntfy.crussell.io |


