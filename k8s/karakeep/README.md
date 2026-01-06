# Karakeep Migration Guide

Migrating from Docker Compose on k2 (192.168.20.62) to k8s cluster.

## Pre-Migration: Backup Data from k2

SSH to k2 and backup the docker volumes:

```bash
# On k2 (192.168.20.62)
cd /tmp

# Stop karakeep to ensure data consistency
cd ~/docker/karakeep  # or wherever your docker-compose.yml is
docker-compose down

# Backup the main app data (contains db.db and other files)
docker run --rm -v karakeep-app-data:/data -v /tmp:/backup busybox tar czf /backup/karakeep-app-data.tar.gz -C /data .

# Backup meilisearch data
docker run --rm -v karakeep-data:/data -v /tmp:/backup busybox tar czf /backup/karakeep-meili-data.tar.gz -C /data .
```

Copy backups to your local machine or directly to a k8s node:

```bash
# From your local machine
scp k2:/tmp/karakeep-*.tar.gz /tmp/
```

## Step 1: Deploy Karakeep

Secrets are already configured in `helmchart.yaml` (committed to git for simplicity).
A backup copy exists in `secrets.yaml` (gitignored).

```bash
# Apply the helm chart
kubectl apply -f helmchart.yaml

# Wait for namespace to be created, then apply nodeport
kubectl apply -f nodeport.yaml

# Watch deployment progress
kubectl -n karakeep get pods -w
```

## Step 2: Restore Data

Once the pods are running, restore the backed-up data:

```bash
# Get the karakeep pod name
KARAKEEP_POD=$(kubectl -n karakeep get pods -l app.kubernetes.io/name=karakeep -o jsonpath='{.items[0].metadata.name}')

# Copy and restore app data
kubectl cp /tmp/karakeep-app-data.tar.gz karakeep/$KARAKEEP_POD:/tmp/
kubectl exec -n karakeep $KARAKEEP_POD -- tar xzf /tmp/karakeep-app-data.tar.gz -C /data

# Get the meilisearch pod name
MEILI_POD=$(kubectl -n karakeep get pods -l app.kubernetes.io/name=meilisearch -o jsonpath='{.items[0].metadata.name}')

# Copy and restore meilisearch data
kubectl cp /tmp/karakeep-meili-data.tar.gz karakeep/$MEILI_POD:/tmp/
kubectl exec -n karakeep $MEILI_POD -- tar xzf /tmp/karakeep-meili-data.tar.gz -C /meili_data

# Restart the pods to pick up restored data
kubectl -n karakeep rollout restart deployment karakeep
kubectl -n karakeep rollout restart deployment karakeep-meilisearch
```

## Step 3: Verify

Access Karakeep at: http://192.168.20.32:30322

Check logs if needed:

```bash
kubectl -n karakeep logs -l app.kubernetes.io/name=karakeep -f
```

## Notes

- The homedash sidecar from your docker-compose is not included in the Helm chart. If you need it, you can deploy it separately.
- Make sure to use the same `MEILI_MASTER_KEY` as your old deployment, otherwise meilisearch won't be able to read the existing data.

