# Open WebUI

Open WebUI is a self-hosted web interface for LLMs.

## Deployment

Apply the manifests to deploy Open WebUI to the cluster:

```bash
kubectl apply -f k8s/open-webui/
```

The k3s built-in Helm controller will automatically install the Helm chart.

## Configuration

- **Database**: Uses SQLite (default) stored in a Longhorn-backed PVC
- **Storage**: 10Gi Longhorn persistent volume
- **Backups**: Configured via Longhorn UI (S3 target)
- **Authentication**: Disabled (WEBUI_AUTH=false)
- **Telemetry**: All telemetry and analytics disabled
- **NodePort**: 30082
- **Domain**: openwebui.crussell.io (via Caddy reverse proxy)

## Accessing

The service is exposed via NodePort 30082 and routed through Caddy at `openwebui.crussell.io`.

## Migration from Docker

This replaces the Docker Compose setup in `k3/docker/openwebui/`. 

To migrate data from the old Docker volume:
1. Deploy to Kubernetes and verify it works
2. Stop the Docker container
3. Copy data from the Docker volume to the PVC if needed
4. Remove the old Docker Compose setup

## Verification

Check the deployment status:

```bash
kubectl get pods -n open-webui
kubectl get pvc -n open-webui
kubectl get svc -n open-webui
```

View logs:

```bash
kubectl logs -n open-webui -l app.kubernetes.io/name=open-webui
```












