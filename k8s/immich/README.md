# Immich

Self-hosted photo and video backup solution deployed on Kubernetes.

## Overview

Immich is a self-hosted backup solution for photos and videos from mobile devices.

## Architecture

- **Database**: CloudNative PostgreSQL with vectorchord extension (required for AI features)
- **Cache/Queue**: Valkey (Redis-compatible)
- **Storage**: NFS mount for library (existing TrueNAS share)
- **ML Models**: Longhorn-backed PVC for machine learning cache

## Deployment

```bash
# Apply all manifests
kubectl apply -f k8s/immich/

# Or apply individually
kubectl apply -f k8s/immich/postgres-cluster.yaml
kubectl apply -f k8s/immich/pvc-library.yaml
kubectl apply -f k8s/immich/helmchart.yaml
kubectl apply -f k8s/immich/nodeport.yaml
```

## Configuration

### Secrets

Secrets are configured inline in `helmchart.yaml` for simplicity. 
A backup reference exists in `secrets.yaml.example` (gitignored).

**Important**: Change the default database password in production!

### Storage

- **Library**: NFS share mounted from TrueNAS (`192.168.20.31:/mnt/tank/photos`)
- **PostgreSQL**: 50Gi Longhorn volume
- **ML Cache**: 10Gi Longhorn volume
- **Redis**: 5Gi Longhorn volume

## Access

- **Domain**: photos.crussell.io
- **NodePort**: 30086
- **Internal Service**: immich-server.immich.svc:2283

## Maintenance

### Check pod status
```bash
kubectl get pods -n immich
```

### View logs
```bash
kubectl logs -n immich -l app.kubernetes.io/component=server
kubectl logs -n immich -l app.kubernetes.io/component=machine-learning
```

### Database operations
```bash
# Connect to database
kubectl exec -it -n immich immich-database-1 -- psql -U immich immich
```

### Backup considerations

The photo library is stored on NFS (TrueNAS) which should have its own backup strategy.
Database backups can be configured via CloudNative PG's built-in backup features.

## Migration from Docker

To migrate your existing Docker Immich instance to Kubernetes:

### Prerequisites
- Docker Immich must be running on k4
- Kubernetes Immich is deployed and running
- Both use the same NFS library mount (`/mnt/immich`)

### Migration Steps

**Step 1: Create database backup on k4**
```bash
ssh k4
cd ~/cn/k4/docker/immich
docker exec -t immich_postgres pg_dump -U postgres -d immich -Fc > /mnt/immich/backups/k8s-migration/immich-db-backup.sql
```

**Step 2: Stop Docker Immich**
```bash
docker compose stop
```

**Step 3: Scale down Kubernetes Immich**
```bash
kubectl scale deployment -n immich immich-server --replicas=0
kubectl scale deployment -n immich immich-machine-learning --replicas=0
```

**Step 4: Restore database to Kubernetes**
```bash
# Copy backup to restore helper
cat /mnt/immich/backups/k8s-migration/immich-db-backup.sql | kubectl exec -i -n immich db-restore-helper -- tee /tmp/backup.sql > /dev/null

# Restore database
kubectl exec -n immich db-restore-helper -- pg_restore -h immich-database-rw -U postgres -d immich --clean --if-exists /tmp/backup.sql
```

**Step 5: Start Kubernetes Immich**
```bash
kubectl scale deployment -n immich immich-server --replicas=1
kubectl scale deployment -n immich immich-machine-learning --replicas=1
```

**Step 6: Verify migration**
- Visit https://photos.crussell.io
- Log in with your existing credentials
- Verify photos are accessible

## Uninstall

```bash
kubectl delete -f k8s/immich/
```

**Note**: This will NOT delete the NFS-mounted library data.
