{ lib, pkgs, config, ... }:

let
  cfg = config.services.k3sHA;
in
{
  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d /var/lib/rancher/k3s/server/manifests 0755 root root -"
      "L+ /var/lib/rancher/k3s/server/manifests/kube-vip.yaml - - - - ${pkgs.writeText "kube-vip.yaml" ''
        apiVersion: v1
        kind: ServiceAccount
        metadata:
          name: kube-vip
          namespace: kube-system
        ---
        apiVersion: rbac.authorization.k8s.io/v1
        kind: ClusterRole
        metadata:
          name: kube-vip-role
        rules:
        - apiGroups: [""]
          resources: ["services", "endpoints", "nodes", "pods", "configmaps"]
          verbs: ["get", "list", "watch", "create", "update", "patch"]
        - apiGroups: ["coordination.k8s.io"]
          resources: ["leases"]
          verbs: ["get", "list", "watch", "create", "update", "patch"]
        ---
        apiVersion: rbac.authorization.k8s.io/v1
        kind: ClusterRoleBinding
        metadata:
          name: kube-vip-binding
        roleRef:
          apiGroup: rbac.authorization.k8s.io
          kind: ClusterRole
          name: kube-vip-role
        subjects:
        - kind: ServiceAccount
          name: kube-vip
          namespace: kube-system
        ---
        apiVersion: apps/v1
        kind: DaemonSet
        metadata:
          name: kube-vip-ds
          namespace: kube-system
          labels:
            app: kube-vip
        spec:
          selector:
            matchLabels:
              app: kube-vip
          template:
            metadata:
              labels:
                app: kube-vip
            spec:
              serviceAccountName: kube-vip
              hostNetwork: true
              dnsPolicy: ClusterFirstWithHostNet
              priorityClassName: system-node-critical
              tolerations:
              - operator: Exists
              nodeSelector:
                node-role.kubernetes.io/control-plane: "true"
              containers:
              - name: kube-vip
                image: ghcr.io/kube-vip/kube-vip:v0.8.0
                imagePullPolicy: IfNotPresent
                args: ["manager"]
                securityContext:
                  capabilities:
                    add:
                    - NET_ADMIN
                    - NET_RAW
                env:
                - name: address
                  value: "${cfg.vip}"
                - name: interface
                  value: "eth0"
                - name: vip_cidr
                  value: "32"
                - name: vip_arp
                  value: "true"
                - name: cp_enable
                  value: "true"
                - name: lb_enable
                  value: "false"
                - name: svc_enable
                  value: "false"
                - name: prometheus_enable
                  value: "false"
                - name: bgp_enable
                  value: "false"
                - name: ddns_enable
                  value: "false"
                - name: port
                  value: "6443"
                resources:
                  requests:
                    cpu: 20m
                    memory: 32Mi
      ''}"
    ];
  };
}



