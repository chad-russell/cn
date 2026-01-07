#!/bin/bash
# Restore audiobookshelf data from backups to k8s

set -e

echo "Getting audiobookshelf pod name..."
ABS_POD=$(kubectl -n audiobookshelf get pods -l app=audiobookshelf -o jsonpath='{.items[0].metadata.name}')

if [ -z "$ABS_POD" ]; then
    echo "Error: No audiobookshelf pod found. Is it running?"
    exit 1
fi

echo "Found pod: $ABS_POD"
echo ""

echo "Copying backups to pod..."
kubectl cp /tmp/audiobookshelf-audiobooks.tar.gz audiobookshelf/$ABS_POD:/tmp/
kubectl cp /tmp/audiobookshelf-podcasts.tar.gz audiobookshelf/$ABS_POD:/tmp/
kubectl cp /tmp/audiobookshelf-config.tar.gz audiobookshelf/$ABS_POD:/tmp/
kubectl cp /tmp/audiobookshelf-metadata.tar.gz audiobookshelf/$ABS_POD:/tmp/

echo ""
echo "Extracting audiobooks..."
kubectl exec -n audiobookshelf $ABS_POD -- tar xzf /tmp/audiobookshelf-audiobooks.tar.gz -C /audiobooks

echo "Extracting podcasts..."
kubectl exec -n audiobookshelf $ABS_POD -- tar xzf /tmp/audiobookshelf-podcasts.tar.gz -C /podcasts

echo "Extracting config..."
kubectl exec -n audiobookshelf $ABS_POD -- tar xzf /tmp/audiobookshelf-config.tar.gz -C /config

echo "Extracting metadata..."
kubectl exec -n audiobookshelf $ABS_POD -- tar xzf /tmp/audiobookshelf-metadata.tar.gz -C /metadata

echo ""
echo "Cleaning up temporary files in pod..."
kubectl exec -n audiobookshelf $ABS_POD -- rm -f /tmp/audiobookshelf-*.tar.gz

echo ""
echo "Restarting deployment to pick up restored data..."
kubectl -n audiobookshelf rollout restart deployment audiobookshelf

echo ""
echo "Waiting for pod to be ready..."
kubectl -n audiobookshelf rollout status deployment audiobookshelf

echo ""
echo "✅ Restore complete!"
echo "Access audiobookshelf at: http://192.168.20.32:30337"












