# Papra

Papra is a self-hosted application for managing personal resources.

## Deployment

Apply the manifests to deploy Papra to the cluster:

```bash
kubectl apply -f k8s/papra/
```

## Configuration

- **Storage**: 10Gi Longhorn persistent volume for app data
- **Port**: 1221
- **NodePort**: 30083
- **Domain**: papra.internal.crussell.io
- **Timezone**: America/New_York
- **AUTH_SECRET**: Set to a custom value (default: `papra-k8s-auth-secret-change-me-in-production`)
  - ⚠️ **Important**: For production use, change this to a secure random string
  - Generate a secure secret: `openssl rand -base64 32`

## Accessing

The service is exposed via NodePort 30083 and should be routed through Caddy at `papra.internal.crussell.io`.

## Migration from Docker

This replaces the Docker Compose setup in `k2/docker/papra/`.

To migrate data from the old Docker volume:
1. Deploy to Kubernetes and verify it works
2. Stop the Docker container
3. Copy data from the Docker volume to the PVC:
   ```bash
   # Get the PVC volume details
   kubectl get pvc -n papra
   
   # Copy data from Docker volume to Longhorn PVC
   # (specific steps will depend on your setup)
   ```
4. Remove the old Docker Compose setup

## Verification

Check the deployment status:

```bash
kubectl get pods -n papra
kubectl get pvc -n papra
kubectl get svc -n papra
```

View logs:

```bash
kubectl logs -n papra -l app=papra
```

