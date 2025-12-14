{ config, pkgs, lib, ... }:

let
  # Write kubeconfig directly to ~/.kube/config
  # This is the standard location that all tools expect, including sandboxed
  # apps like Cursor/VS Code that can't access /etc/rancher/k3s/
  k3sConfigPath = "/home/crussell/.kube/config";
in
{
  # Enable k3s as a single-node cluster for local development
  services.k3s = {
    enable = true;
    role = "server";
    
    extraFlags = toString [
      # Disable components not needed for local dev to keep it lightweight
      "--disable=traefik"        # Disable Traefik ingress (you can use your own)
      "--disable=servicelb"      # Disable service load balancer
      # "--disable=local-storage" # Uncomment if you want to use your own storage class
      
      # Write kubeconfig to user's home directory so all tools can access it
      "--write-kubeconfig=${k3sConfigPath}"
      "--write-kubeconfig-mode=644"
    ];
  };

  # Ensure ~/.kube exists and is writable by k3s (runs as root initially)
  # The directory is owned by crussell so the user can manage it
  systemd.tmpfiles.rules = [
    "d /home/crussell/.kube 0755 crussell users -"
  ];

  # Install kubectl and other useful k8s tools for development
  environment.systemPackages = with pkgs; [
    kubectl              # Kubernetes CLI
    kubernetes-helm      # Helm package manager for Kubernetes
    k9s                  # Terminal UI for Kubernetes
    kustomize            # Kubernetes native configuration management
  ];

  # Set KUBECONFIG environment variable (though ~/.kube/config is the default)
  environment.variables = {
    KUBECONFIG = k3sConfigPath;
  };

  # Local development hostnames for k3s ingress
  networking.hosts = {
    "127.0.0.1" = [ "hb-api.gloo.local" "hb-web.gloo.local" "storyhub.gloo.local" "gpl.gloo.local" "polymer.gloo.local" "minio.gloo.local" ];
  };
}
