# ── Wake-on-LAN enablement (shared) ────────────────────────────────
#
# Arms NICs for WoL at boot with `ethtool -s <iface> wol g` so the host
# responds to magic packets while powered off. Added after the
# 2026-09-08 power outage: bees + nas were power-cut and sat dark until
# physically powered on. Neither BIOS exposes a software-writable
# "restore AC power loss" option, so the recovery path is (1) BIOS
# auto-power-on flipped by hand (primary, see docs) and (2) WoL from
# survivor host bee (hosts/bee/wol-watch.nix) — this module is (2)'s
# target half.
#
# Verified NIC support: Intel E610 (bees enp196s0f0/f1), Intel I226-V
# (nas enp2s0/enp3s0). The ethtool Wake-on flags reset to firmware
# defaults on every boot, which is why this must run at activation
# rather than once. Idle/unplugged ports are armed too, so the watcher
# keeps working if a cable ever moves to the other port.

{ config, lib, pkgs, ... }:

let cfg = config.cn.wol-enable;
in {
  options.cn.wol-enable = {
    enable = lib.mkEnableOption "arming NICs for Wake-on-LAN at boot";
    interfaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "NIC names to arm for Wake-on-LAN (ethtool wol g)";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.wol-enable = {
      description = "Arm NICs for Wake-on-LAN (ethtool wol g)";
      after = [ "network-pre.target" ];
      before = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [ pkgs.ethtool pkgs.iproute2 ];
      script = lib.concatStrings (map (ifc: ''
        if ip link show "${ifc}" >/dev/null 2>&1; then
          if ethtool -s "${ifc}" wol g; then
            echo "wol-enable: ${ifc} armed (wol g)"
          else
            echo "wol-enable: WARNING ${ifc} refused wol g (no WoL support?)" >&2
          fi
        else
          echo "wol-enable: ${ifc} absent, skipping"
        fi
      '') cfg.interfaces);
    };
  };
}
