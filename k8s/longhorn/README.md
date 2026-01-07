# Longhorn Storage Configuration

## Backup Configuration

This directory contains the Longhorn storage configuration with S3 backup support.

### Files

- `helmchart.yaml` - Main Longhorn Helm chart configuration (includes S3 target settings)
- `secrets.yaml` - S3 credentials (gitignored - you must create this manually)

### Setting Up Backups

#### 1. Configure S3 Credentials

Edit `secrets.yaml` and add your AWS credentials:

```yaml
stringData:
  AWS_ACCESS_KEY_ID: "your-access-key"
  AWS_SECRET_ACCESS_KEY: "your-secret-key"
  AWS_ENDPOINTS: "https://s3.us-east-1.amazonaws.com"
```

#### 2. Update Backup Target

Edit `helmchart.yaml` and set your S3 bucket name:

```yaml
backupTarget: "s3://crussell-longhorn-backups@us-east-1/"
```

#### 3. Apply the Configuration

```bash
# Apply the secret
kubectl apply -f k8s/longhorn/secrets.yaml

# The helmchart.yaml is automatically applied by k3s Helm controller
# If needed, force update:
kubectl apply -f k8s/longhorn/helmchart.yaml
```

### 4. Manage Schedules (via UI)

Recurring backup jobs are managed through the Longhorn UI:

1. **Access Longhorn UI**: `http://longhorn-frontend.longhorn-system.svc` (via NodePort or Port Forward)
2. **Create Recurring Job**:
   - Go to **Recurring Job** tab.
   - Click **Create Recurring Job**.
   - Configure your schedule (e.g., Daily at 3 AM).
3. **Assign to Volumes**:
   - Go to **Volume** tab.
   - Select volumes (e.g., `open-webui`).
   - Click **Update Recurring Jobs**.
   - Assign your created job.

### Restoring from Backup

1. Navigate to **Backup** tab in the UI.
2. Select the backup you want to restore.
3. Click **Restore** to create a new volume from the backup.
