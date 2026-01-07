# Audiobookshelf Migration Guide

Migrating from Docker Compose on k3 (192.168.20.63) to k8s cluster.

## Pre-Migration: Backup Data from k3

SSH to k3 and backup the docker volumes:

```bash
# On k3 (192.168.20.63)
cd /tmp

# Stop audiobookshelf to ensure data consistency
cd ~/docker/audiobookshelf  # or wherever your docker-compose.yml is
docker-compose down

# Backup all four volumes
docker run --rm -v audiobookshelf-audiobooks:/data -v /tmp:/backup busybox tar czf /backup/audiobookshelf-audiobooks.tar.gz -C /data .
docker run --rm -v audiobookshelf-podcasts:/data -v /tmp:/backup busybox tar czf /backup/audiobookshelf-podcasts.tar.gz -C /data .
docker run --rm -v audiobookshelf-config:/data -v /tmp:/backup busybox tar czf /backup/audiobookshelf-config.tar.gz -C /data .
docker run --rm -v audiobookshelf-metadata:/data -v /tmp:/backup busybox tar czf /backup/audiobookshelf-metadata.tar.gz -C /data .
```

Copy backups to your local machine:

```bash
# From your local machine
scp crussell@192.168.20.63:/tmp/audiobookshelf-*.tar.gz /tmp/
```

## Step 1: Deploy Audiobookshelf

```bash
# Apply the manifest
kubectl apply -f k8s/audiobookshelf/manifest.yaml

# Watch deployment progress
kubectl -n audiobookshelf get pods -w
```

## Step 2: Restore Data

Once the pod is running, restore the backed-up data:

```bash
# Get the pod name
ABS_POD=$(kubectl -n audiobookshelf get pods -l app=audiobookshelf -o jsonpath='{.items[0].metadata.name}')

# Copy all backups to the pod
kubectl cp /tmp/audiobookshelf-audiobooks.tar.gz audiobookshelf/$ABS_POD:/tmp/
kubectl cp /tmp/audiobookshelf-podcasts.tar.gz audiobookshelf/$ABS_POD:/tmp/
kubectl cp /tmp/audiobookshelf-config.tar.gz audiobookshelf/$ABS_POD:/tmp/
kubectl cp /tmp/audiobookshelf-metadata.tar.gz audiobookshelf/$ABS_POD:/tmp/

# Extract all data to their respective directories
kubectl exec -n audiobookshelf $ABS_POD -- tar xzf /tmp/audiobookshelf-audiobooks.tar.gz -C /audiobooks
kubectl exec -n audiobookshelf $ABS_POD -- tar xzf /tmp/audiobookshelf-podcasts.tar.gz -C /podcasts
kubectl exec -n audiobookshelf $ABS_POD -- tar xzf /tmp/audiobookshelf-config.tar.gz -C /config
kubectl exec -n audiobookshelf $ABS_POD -- tar xzf /tmp/audiobookshelf-metadata.tar.gz -C /metadata

# Restart the pod to pick up restored data
kubectl -n audiobookshelf rollout restart deployment audiobookshelf
```

## Step 3: Verify

Access Audiobookshelf at: http://192.168.20.32:30337

Check logs if needed:

```bash
kubectl -n audiobookshelf logs -l app=audiobookshelf -f
```

## Notes

- **Storage sizes** are set to:
  - audiobooks: 100Gi (adjust based on your library size)
  - podcasts: 50Gi
  - config: 5Gi
  - metadata: 10Gi
- The original port 13378 is mapped to NodePort 30337 for easier access
- You can adjust storage sizes in the manifest before deploying if needed












