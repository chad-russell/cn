# ── sweatshop sandbox host: rootless podman API over TCP on Nebula ────
#
# sweatshop (bee 10.10.0.12:3330) creates per-thread sandbox containers
# on remote engines through dockerode → this API. One line per host:
#   homelab.sweatshopSandboxHost.enable = true;
#
# Shape: crussell user socket+service pair (linger is on, so it starts at
# boot with no login). The socket binds ONLY <nebula-ip>:8750; podman is
# socket-activated (`podman system service --time=0`, no address arg).
#
# Boot race: user units can't order after the SYSTEM nebula@homelab unit,
# so the socket uses FreeBind=yes and binds before the tun address exists
# (same fix as dsh-web-proxy in modules/dsh.nix).
#
# SECURITY: this API is root-equivalent for crussell on the host — anyone
# who reaches it can run containers as that user. Access control is the
# Nebula inbound firewall below (TCP 8750 from bee 10.10.0.12/32 only);
# networking.firewall is disabled fleet-wide, so the interface-scoped
# opening only matters if it is ever re-enabled.
{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.sweatshopSandboxHost;
  hostMeta = import ../lib/host-meta.nix;
  nebulaIp = hostMeta.${config.networking.hostName}.nebula;
  port = cfg.port;
  portStr = toString port;
in {
  options.homelab.sweatshopSandboxHost = {
    enable = lib.mkEnableOption
      "rootless podman API on <nebula-ip>:8750 for sweatshop sandboxes";
    port = lib.mkOption {
      type = lib.types.port;
      default = 8750;
    };
    allowedFrom = lib.mkOption {
      type = lib.types.str;
      default = "${hostMeta.bee.nebula}/32";
      description =
        "Nebula CIDR allowed to reach the API (the sweatshop host).";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.user.sockets.sweatshop-podman-api = {
      description = "sweatshop podman API socket (${nebulaIp}:${portStr})";
      wantedBy = [ "sockets.target" ];
      unitConfig.ConditionUser = "crussell";
      socketConfig = {
        ListenStream = "${nebulaIp}:${portStr}";
        FreeBind = true;
      };
    };

    systemd.user.services.sweatshop-podman-api = {
      description = "sweatshop podman API (socket-activated, rootless)";
      requires = [ "sweatshop-podman-api.socket" ];
      after = [ "sweatshop-podman-api.socket" ];
      unitConfig.ConditionUser = "crussell";
      # newuidmap/newgidmap (setuid wrappers) + conmon/crun via the system
      # profile — the default user-unit PATH lacks /run/wrappers/bin.
      environment.PATH =
        lib.mkForce "/run/wrappers/bin:/run/current-system/sw/bin";
      serviceConfig = {
        # Mirrors upstream podman.service: KillMode=process so restarting
        # the API never takes running sandboxes (or their rootlessport
        # forwarders) down with it.
        Type = "exec";
        KillMode = "process";
        Delegate = true;
        ExecStart = "${pkgs.podman}/bin/podman system service --time=0";
      };
    };

    # Nebula rules are allow-only, so narrowing one port means replacing
    # the module's any/any rule with ranges around it.
    services.nebula.networks.homelab.firewall.inbound = lib.mkForce [
      {
        port = "1-${toString (port - 1)}";
        proto = "any";
        host = "any";
      }
      {
        port = "${toString (port + 1)}-65535";
        proto = "any";
        host = "any";
      }
      {
        port = "any";
        proto = "icmp";
        host = "any";
      }
      {
        port = "fragment";
        proto = "any";
        host = "any";
      }
      {
        port = portStr;
        proto = "tcp";
        cidr = cfg.allowedFrom;
      }
    ];

    networking.firewall.interfaces."nebula.homelab".allowedTCPPorts = [ port ];
  };
}
