# SearXNG

SearXNG is a privacy-respecting metasearch engine.

## Deployment

Apply the manifests to deploy SearXNG to the cluster:

```bash
kubectl apply -f k8s/searxng/
```

The k3s built-in Helm controller will automatically install the Helm chart.

## Configuration

- **Helm Chart**: [self-hosters-by-night/searxng](https://artifacthub.io/packages/helm/self-hosters-by-night/searxng)
- **Storage**:
  - Config: 1Gi Longhorn PVC
  - Cache: 2Gi Longhorn PVC
  - Valkey/Redis data: 1Gi Longhorn PVC
- **Components**:
  - SearXNG: Main search engine (port 8080)
  - Valkey: Redis-compatible cache (port 6379)
- **NodePort**: 30084
- **Domain**: searxng.internal.crussell.io
- **Custom ConfigMaps**:
  - `searxng-settings-manual`: Enables JSON format and disables limiter
  - `searxng-limiter-manual`: Configures trusted proxies for bot detection

## Accessing

The service is exposed via NodePort 30084 and should be routed through Caddy at `searxng.internal.crussell.io`.

## Custom Configuration

The SearXNG deployment uses custom ConfigMaps to override default settings:

### settings-manual.yaml

Enables JSON API format and disables the rate limiter for internal use:

```yaml
use_default_settings: true
server:
  limiter: false
  secret_key: "default-secret-key-change-me"  # Change this!
search:
  formats:
    - html
    - json
    - csv
    - rss
```

### limiter-manual.yaml

Configures the bot detection to trust the Caddy reverse proxy:

```toml
[botdetection]
trusted_proxies = [
  '0.0.0.0/0',        # Trust ALL (Debug/Internal only)
  '::/0',
]
```

**Security Note**: The `0.0.0.0/0` trusted proxy is for debugging. For production, restrict to specific networks:
- `192.168.20.0/24` - Caddy server network
- `10.42.0.0/16` - Pod/service network
- `10.43.0.0/16` - Cluster/service network

To modify configuration, edit the ConfigMap YAML files and reapply:
```bash
kubectl apply -f k8s/searxng/settings-manual.yaml
kubectl apply -f k8s/searxng/limiter-manual.yaml
kubectl rollout restart deployment -n searxng searxng
```

## Migration from Docker

This replaces the Docker Compose setup in `k3/docker/searxng/`.

### Data Migration

If you have custom searxng configuration or want to preserve cache:

1. Deploy to Kubernetes and verify it works
2. Stop the Docker containers
3. Copy config from Docker volumes to PVCs if needed:
   - `searxng-config` → searxng config PVC
   - `searxng-cache` → searxng cache PVC
   - `searxng-valkey-data` → valkey data PVC
4. Remove the old Docker Compose setup

**Note**: For most users, no data migration is needed as SearXNG configuration is typically minimal and cache can be rebuilt.

## Verification

Check the deployment status:

```bash
kubectl get pods -n searxng
kubectl get pvc -n searxng
kubectl get svc -n searxng
```

View logs:

```bash
kubectl logs -n searxng -l app.kubernetes.io/name=searxng
kubectl logs -n searxng -l app.kubernetes.io/name=redis
```

## Caddy Configuration

Add to your Caddyfile (proxy headers are required for bot detection):

```caddy
searxng.internal.crussell.io {
    reverse_proxy 192.168.20.32:30084 {
        header_up X-Forwarded-For {remote_host}
        header_up X-Real-IP {remote_host}
    }
}
```

The `X-Forwarded-For` and `X-Real-IP` headers are required for SearXNG's bot detection to work correctly when accessed through a reverse proxy.














