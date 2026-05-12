# ── nas Disk Layout (UGREEN DXP4800 Pro) ───────────────────────────
#
# Hardware:
#   - Intel Core i3-1315U (6C/7T: 2P+4E)
#   - 8GB DDR5 5600 (expandable to 96GB)
#   - 128GB onboard SSD (system flash)
#   - 2× M.2 NVMe SSD slots
#   - 4× 3.5" SATA bays (populated with 4× HDD from TrueNAS)
#   - 1× 10GbE, 1× 2.5GbE
#
# Layout:
#   M.2 NVMe slot 1: NixOS root
#     p1: 1G    EFI (systemd-boot)
#     p2: 8G    swap
#     p3: rest  btrfs subvolumes (@, @home, @nix, @var-log, @srv)
#
#   4× SATA HDD: btrfs RAID1 data pool
#     data=raid1, metadata=raid1
#     Subvolumes: media, photos, surveillance, backups, scratch
#     ~50% raw capacity usable (mirrored)
#
# NOTE: Device paths are placeholders until first boot with installer.
#   lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
#   ls -la /dev/disk/by-id/
# Then update device = "..." lines to stable by-id paths.

{
  disko.devices = {
    disk = {
      # ── M.2 NVMe: NixOS root ───────────────────────────────────
      # TODO: Update with actual by-id path from installer
      nvme-root = {
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

      # ── 4× SATA HDD: btrfs RAID1 data pool ─────────────────────
      #
      # All 4 HDDs form a single btrfs RAID1 filesystem.
      # data=raid1: every data block exists on 2 devices
      # metadata=raid1: every metadata block exists on 2 devices
      # Survives any single disk failure, and often two.
      # Usable capacity: ~50% of raw (mirrored).
      #
      # disko creates the filesystem on hdd-1 and passes the other
      # 3 devices via extraArgs. mkfs.btrfs handles them all at once.
      hdd-1 = {
        type = "disk";
        device = "/dev/sda";
        content = {
          type = "btrfs";
          extraArgs = [
            "-f"
            "-d raid1"
            "-m raid1"
            "/dev/sdb"
            "/dev/sdc"
            "/dev/sdd"
          ];
          subvolumes = {
            "@media" = {
              mountpoint = "/pool/media";
              mountOptions = [ "compress=zstd" "noatime" ];
            };
            "@photos" = {
              mountpoint = "/pool/photos";
              mountOptions = [ "compress=zstd" "noatime" ];
            };
            "@surveillance" = {
              mountpoint = "/pool/surveillance";
              # Less compression — video is already compressed
              mountOptions = [ "compress=lzo" "noatime" "nodatacow" ];
            };
            "@backups" = {
              mountpoint = "/pool/backups";
              mountOptions = [ "compress=zstd" "noatime" ];
            };
            "@scratch" = {
              mountpoint = "/pool/scratch";
              # No compression, no COW — disposable data
              mountOptions = [ "noatime" "nodatacow" ];
            };
          };
        };
      };
    };
  };
}
