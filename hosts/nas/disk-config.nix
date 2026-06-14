# ── nas Disk Layout (UGREEN DXP4800) ──────────────────────────────
#
# Hardware detected 2026-05-12 from NixOS installer:
#   CPU: Intel N100 (4C/4T, Alder Lake-N)
#   RAM: 32GB DDR5
#   NICs: 2× Intel I226-V (2.5GbE) — enp2s0, enp3s0
#   NVMe: SPCC M.2 PCIe SSD 512GB (nvme-SPCC_M.2_PCIe_SSD_4E69074C13BF00015309)
#   HDD 1: HGST Ultrastar HUH721212ALE601 12TB (ata-HUH721212ALE601_2AG2TBBY)
#   HDD 2: HGST Ultrastar HUH721212ALE601 12TB (ata-HUH721212ALE601_8CKU7ETF)
#   HDD 3: Seagate SkyHawk ST12000VX0007 12TB (ata-ST12000VX0007-2GU116_ZJV09H1V)
#   HDD 4: Seagate SkyHawk ST12000VX0007 12TB (ata-ST12000VX0007-2GU116_ZJV4RWH4)
#   eMMC: 29.1G onboard flash (UGOS Pro) — DO NOT TOUCH
#
# Layout:
#   NVMe (512GB): NixOS root
#     p1: 1G    EFI (systemd-boot)
#     p2: 8G    swap
#     p3: rest  btrfs subvolumes (@, @home, @nix, @var-log, @srv)
#
#   4× 12TB HDD: btrfs RAID1 data pool (~12TB usable)
#     data=raid1, metadata=raid1
#     Subvolumes: media, photos, surveillance, backups, scratch
#
#   eMMC (mmcblk0): UGOS Pro factory install — left untouched

{
  disko.devices = {
    disk = {
      # ── NVMe: NixOS root (SPCC 512GB) ──────────────────────────
      nvme-root = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-SPCC_M.2_PCIe_SSD_4E69074C13BF00015309";
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

      # ── 4× 12TB HDD: btrfs RAID1 data pool ─────────────────────
      #
      # All 4 HDDs form a single btrfs RAID1 filesystem.
      # data=raid1: every data block exists on 2 devices
      # metadata=raid1: every metadata block exists on 2 devices
      # Survives any single disk failure, and often two.
      # Usable capacity: ~12TB (50% of 48TB raw).
      #
      # disko creates the filesystem on hdd-1 and passes the other
      # 3 devices via extraArgs. mkfs.btrfs handles them all at once.
      hdd-1 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-HUH721212ALE601_2AG2TBBY";
        content = {
          type = "btrfs";
          extraArgs = [
            "-f"
            "-d raid1"
            "-m raid1"
            "/dev/disk/by-id/ata-HUH721212ALE601_8CKU7ETF"
            "/dev/disk/by-id/ata-ST12000VX0007-2GU116_ZJV09H1V"
            "/dev/disk/by-id/ata-ST12000VX0007-2GU116_ZJV4RWH4"
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
              # Less compression — video is already compressed.
              # nodatacow: better write performance for continuous recording.
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

  # Mount /home in the initrd (before NixOS activation) so agenix can decrypt
  # secrets using the identity at /home/crussell/.config/age/key.txt at boot.
  # Without this, a separate /home subvolume races agenix and age-encrypted
  # secrets (and services that depend on them) fail to come up after a reboot.
  # See modules/base-server.nix (age.identityPaths).
  fileSystems."/home".neededForBoot = true;
}
