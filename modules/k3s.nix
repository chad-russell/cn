{ config, pkgs, lib, ... }:

let
  # Write kubeconfig directly to a specific file for the 'gloo' context
  # This avoids overwriting the main config and allows merging
  k3sConfigPath = "/home/crussell/.kube/gloo.yaml";
  homeConfigPath = "/home/crussell/.kube/home-k3s.yaml";
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

  # Post-process the generated config to rename context to 'gloo'
  # This runs as root after k3s starts
  systemd.services.k3s.serviceConfig.ExecStartPost = let
    script = pkgs.writeShellScript "k3s-rename-context" ''
      # Wait for config file to be generated
      while [ ! -f "${k3sConfigPath}" ]; do ${pkgs.coreutils}/bin/sleep 1; done
      
      # Use yq to rename cluster, context, and user to 'gloo'
      ${pkgs.yq-go}/bin/yq -i '
        .clusters[0].name = "gloo" |
        .contexts[0].name = "gloo" |
        .contexts[0].context.cluster = "gloo" |
        .contexts[0].context.user = "gloo" |
        .users[0].name = "gloo" |
        .current-context = "gloo"
      ' "${k3sConfigPath}"
      
      # Ensure correct ownership
      ${pkgs.coreutils}/bin/chown crussell:users "${k3sConfigPath}"
    '';
  in [ "${script}" ];

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
    yq-go                # YAML processor (useful for config manipulation)
  ];

  # Set KUBECONFIG environment variable to load both contexts
  environment.variables = {
    KUBECONFIG = "${k3sConfigPath}:${homeConfigPath}";
  };

  # Local development hostnames for k3s ingress
  networking.hosts = {
    "127.0.0.1" = [ "hb-api.gloo.local" "hb-web.gloo.local" "storyhub.gloo.local" "gpl.gloo.local" "polymer.gloo.local" "minio.gloo.local" ];
  };
}
