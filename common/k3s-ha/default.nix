{ lib, pkgs, config, ... }:

with lib;

let
  cfg = config.services.k3sHA;
in
{
  imports = [
    ./kube-vip.nix
  ];

  options.services.k3sHA = {
    enable = mkEnableOption "k3s HA cluster node";

    nodeIP = mkOption {
      type = types.str;
      description = "IP address of this node";
      example = "192.168.20.62";
    };

    clusterInit = mkOption {
      type = types.bool;
      default = false;
      description = "Whether this is the initial cluster node (only one should be true)";
    };

    tokenFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to the cluster token file (required for non-init nodes)";
    };

    vip = mkOption {
      type = types.str;
      default = "192.168.20.32";
      description = "Virtual IP address for the HA cluster";
    };

    extraFlags = mkOption {
      type = types.str;
      default = "";
      description = "Additional flags to pass to k3s";
    };
  };

  config = mkIf cfg.enable {
    # Validate configuration
    assertions = [
      {
        assertion = cfg.clusterInit || cfg.tokenFile != null;
        message = "services.k3sHA.tokenFile must be set if clusterInit is false";
      }
    ];

    # K3s service configuration
    services.k3s = {
      enable = true;
      role = "server";
      clusterInit = cfg.clusterInit;
      serverAddr = mkIf (!cfg.clusterInit) "https://${cfg.vip}:6443";
      tokenFile = mkIf (!cfg.clusterInit) cfg.tokenFile;
      extraFlags = toString (filter (x: x != "") [
        "--tls-san=${cfg.vip}"
        "--node-ip=${cfg.nodeIP}"
        "--advertise-address=${cfg.nodeIP}"
        "--write-kubeconfig-mode=644"
        "--disable=traefik"
        cfg.extraFlags
      ]);
    };

    # Firewall configuration for k3s
    networking.firewall.allowedTCPPorts = [ 
      6443   # Kubernetes API
      2379   # etcd client
      2380   # etcd peer
      10250  # kubelet
      10251  # kube-scheduler
      10252  # kube-controller-manager
      10257  # kube-controller-manager (secure)
      10259  # kube-scheduler (secure)
    ];
    networking.firewall.allowedUDPPorts = [ 
      8472   # Flannel VXLAN
    ];

    # Longhorn prerequisites
    services.openiscsi = {
      enable = true;
      name = "iqn.2024-12.homelab:${config.networking.hostName}";
    };

    # Required packages for Longhorn
    environment.systemPackages = with pkgs; [
      nfs-utils
      util-linux
    ];

    # Ensure iscsid is running
    systemd.services.iscsid.wantedBy = [ "multi-user.target" ];
  };
}

