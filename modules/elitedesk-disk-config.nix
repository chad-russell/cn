# ── Standard Elitedesk Disk Layout ─────────────────────────────────
#
# Used by ALL k-machines (k1-k4). Identical hardware:
#   - /dev/nvme0n1: 238.5G NVMe
#   - /dev/sda:     1.8T HDD
#
# Layout:
#   NVMe: 512M EFI + 8G swap + ext4 root
#   HDD:  ext4 /mnt/data
#
# This is the layout k3 was originally installed with.
# For already-installed machines, this must match their actual partitions.
# For fresh installs via nixos-anywhere, this is what gets applied.
#
# NOTE: The HDD partition is NOT included here because some machines
# may not want it mounted, or may want it at a different mountpoint.
# Add HDD mounts in per-host configuration.nix if needed.

{ ... }:
{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/nvme0n1";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            swap = {
              size = "8G";
              content = {
                type = "swap";
                resumeDevice = true;
              };
            };
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
          };
        };
      };
      data = {
        type = "disk";
        device = "/dev/sda";
        content = {
          type = "gpt";
          partitions = {
            data = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/mnt/data";
              };
            };
          };
        };
      };
    };
  };
}
