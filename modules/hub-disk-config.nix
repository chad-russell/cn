# ── Hub Disk Layout ────────────────────────────────────────────────
#
# Hardware: Crucial P3 Plus 1TB NVMe (CT1000P3PSSD8)
# RAM: 32GB (+ zram)
# No secondary disk.
#
# Layout:
#   /dev/nvme0n1:
#     p1: 1G    EFI
#     p2: 8G    swap (supplemental to zram)
#     p3: rest  btrfs with subvolumes:
#       @        → /          (root, snapshot-friendly)
#       @home    → /home
#       @nix     → /nix       (nix store)
#       @var-log → /var/log
#       @srv     → /srv       (service data, container volumes)

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
              size = "8G";
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
