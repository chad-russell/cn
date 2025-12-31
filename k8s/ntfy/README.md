# Ntfy

Ntfy is a simple HTTP-based pub-sub notification service.

## Deployment

Apply the manifests to deploy ntfy to the cluster:

```bash
kubectl apply -f k8s/ntfy/
```

The k3s built-in Helm controller will automatically install the Helm chart.

## Configuration

- **Helm Chart**: [ntfy/ntfy](https://artifacthub.io/packages/helm/ntfy/ntfy) (OCI registry)
- **Chart Location**: `oci://codeberg.org/wrenix/helm-charts/ntfy`
- **Image**: binwiederhier/ntfy:v2.11.0
- **Storage**: 
  - Data: 2Gi Longhorn PVC (stores cache, config, and database)
- **NodePort**: 30085
- **Domain**: ntfy.crussell.io (or ntfy.internal.crussell.io)
- **Timezone**: America/New_York
- **Metrics Port**: 9000 (Prometheus metrics)

## Accessing

The service is exposed via NodePort 30085 and should be routed through Caddy at your chosen domain.

## Migration from Docker

This replaces the Docker Compose setup in `k2/docker/ntfy/`.

### Data Migration

If you have existing ntfy configuration or cached data to preserve:

1. Deploy to Kubernetes and verify it works
2. Stop the K8s ntfy pod: `kubectl scale deployment ntfy -n ntfy --replicas=0`
3. Create a migration pod (similar to the papra migration process)
4. Copy data from Docker volumes to the PVC:
   - Docker `ntfy-cache` → PVC at `/var/lib/ntfy/`
   - Docker `ntfy-config` → PVC at `/var/lib/ntfy/`
5. Restart the deployment: `kubectl scale deployment ntfy -n ntfy --replicas=1`
6. Remove the old Docker Compose setup

**Note**: For most users, no data migration is needed. Ntfy will create default configuration on first run.

## Verification

Check the deployment status:

```bash
kubectl get pods -n ntfy
kubectl get pvc -n ntfy
kubectl get svc -n ntfy
```

View logs:

```bash
kubectl logs -n ntfy -l app.kubernetes.io/name=ntfy
```

## Caddy Configuration

Add to your Caddyfile:

```caddy
ntfy.crussell.io {
    reverse_proxy 192.168.20.32:30085
}
```

## Usage

Send notifications:

```bash
# Simple notification
curl -d "Hello from K8s!" https://ntfy.crussell.io/mytopic

# With title
curl -H "Title: Deployment Alert" -d "ntfy deployed successfully!" https://ntfy.crussell.io/mytopic
```

Subscribe to notifications:

```bash
# Command line
curl -s https://ntfy.crussell.io/mytopic/sse

# Or use the ntfy mobile app or web UI
```

