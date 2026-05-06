# ── bees Disk Layout ────────────────────────────────────────────────
#
# Hardware: Crucial P310 2TB NVMe (CT2000P310SSD8)
# RAM: 128 GB (shared with integrated Radeon 8060S GPU; ~32 GB visible to OS)
# No secondary disk. Dual 10GbE Intel E610 NICs.
#
# Layout (modeled after modules/hub-disk-config.nix but larger):
#   /dev/nvme0n1:
#     p1: 1G    EFI
#     p2: 16G   swap (supplemental to zram; large for potential hibernation)
#     p3: rest  btrfs with subvolumes:
#       @        → /          (root, snapshot-friendly)
#       @home    → /home
#       @nix     → /nix       (nix store — will be large)
#       @var     → /var       (service data, container volumes)
#       @var-log → /var/log
#       @srv     → /srv       (application data like linkding, papra, etc.)

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
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            swap = {
              size = "16G";
              content = {
                type = "swap";
                resumeDevice = true;
              };
            };
            root = {
              size = "100%";
              content = {
                type = "btrfs";
                extraArgs = [ "-f" ];
                subvolumes = {
                  "@" = {
                    mountpoint = "/";
                    mountOptions = [ "compress=zstd" "noatime" ];
                  };
                  "@home" = {
                    mountpoint = "/home";
                    mountOptions = [ "compress=zstd" "noatime" ];
                  };
                  "@nix" = {
                    mountpoint = "/nix";
                    mountOptions = [ "compress=zstd" "noatime" ];
                  };
                  "@var" = {
                    mountpoint = "/var";
                    mountOptions = [ "compress=zstd" "noatime" ];
                  };
                  "@var-log" = {
                    mountpoint = "/var/log";
                    mountOptions = [ "compress=zstd" "noatime" ];
                  };
                  "@srv" = {
                    mountpoint = "/srv";
                    mountOptions = [ "compress=zstd" "noatime" ];
                  };
                };
              };
            };
          };
        };
      };
    };
  };
}
