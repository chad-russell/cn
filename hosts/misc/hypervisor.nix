# ── misc: Incus Hypervisor ─────────────────────────────────────────
#
# Turns the HP Z820 into a Proxmox-like VM/container host using Incus.
#
# Prerequisites:
#   1. Enable VT-x + VT-d in BIOS (F10 → Security → System Security)
#   2. Deploy this config: nix run .#deploy -- misc
#   3. Verify: incus version
#
# Usage:
#   incus launch images:debian/trixie --vm xfce-playground -c limits.cpu=4 -c limits.memory=4GiB
#   incus exec xfce-playground -- bash -c "apt update && apt install -y xfce4 xfce4-goodies lightdm"
#   incus console xfce-playground --type vga   # opens SPICE graphical console
#
# Web UI: https://192.168.20.42:8443

{ config, lib, pkgs, ... }:

{
  # ── Incus ────────────────────────────────────────────────────────
  virtualisation.incus = {
    enable = true;
    ui.enable = true;

    preseed = {
      config = {
        "core.https_address" = ":8443";
      };

      networks = [
        {
          name = "incusbr0";
          type = "bridge";
          config = {
            "ipv4.address" = "10.0.200.1/24";
            "ipv4.nat" = "true";
            "ipv4.dhcp.ranges" = "10.0.200.10-10.0.200.200";
          };
        }
      ];

      profiles = [
        {
          name = "default";
          devices = {
            eth0 = {
              name = "eth0";
              network = "incusbr0";
              type = "nic";
            };
            root = {
              path = "/";
              pool = "default";
              size = "50GiB";
              type = "disk";
            };
          };
        }
      ];

      storage_pools = [
        {
          name = "default";
          driver = "dir";
          config = {
            source = "/var/lib/incus/storage-pools/default";
          };
        }
      ];
    };
  };

  # Incus requires nftables (not iptables)
  networking.nftables.enable = true;

  # Trust the Incus bridge so VMs/containers can reach the host and each other
  networking.firewall.trustedInterfaces = [ "incusbr0" ];

  # Allow Incus API access from LAN (for incus remote add + web UI)
  networking.firewall.allowedTCPPorts = [ 8443 ];

  # ── User access ──────────────────────────────────────────────────
  users.users.crussell.extraGroups = [ "incus-admin" ];

  # ── Graphical console support ────────────────────────────────────
  # virt-viewer provides remote-viewer for SPICE console access
  # spice-gtk is already pulled in by the incus module
  environment.systemPackages = with pkgs; [
    virt-viewer     # SPICE client: incus console <vm> --type vga
    spice-gtk       # SPICE GTK client (alternate)
  ];

  # Storage pool directory is created by Incus preseed — don't pre-create it
}
