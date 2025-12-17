# Kubernetes Manifests

This directory contains Kubernetes manifests for applications running on the k3s HA cluster.

## Structure

- `longhorn/` - Longhorn distributed storage system

## How it works

K3s has a built-in Helm controller that automatically applies HelmChart CRDs placed in `/var/lib/rancher/k3s/server/manifests/`. 

To deploy applications:
1. Create a `HelmChart` resource in the appropriate subdirectory
2. Apply it to the cluster: `kubectl apply -f k8s/<app>/`

K3s will automatically install and manage the Helm release.



