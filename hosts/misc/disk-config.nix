# ── misc Disk Layout (HP Z820 — temporary backup target) ───────────
#
# Hardware detected 2026-05-09:
#   sdd: WD Blue SA510 2.5 2TB (ata-WD_Blue_SA510_2.5_2TB_25144ED00458) — SSD
#   sdb: WDC WD40EZAZ-00SF3B0 WD-WX52D31D9RDS — 4TB HDD
#   sdc: WDC WD40EZAZ-00SF3B0 WD-WX22D21882RT — 4TB HDD
#
# Layout:
#   SSD (~2TB): OS root + extra scratch
#     p1: 1G    EFI (systemd-boot)
#     p2: 8G    swap
#     p3: 500G  btrfs subvolumes (@, @home, @nix, @var-log)
#     p4: rest  btrfs mounted at /mnt/extra
#
#   HDD 1 + HDD 2 (~4TB each): Backup pool
#     Raw btrfs, data=single, metadata=raid1
#     ~8TB usable, mounted at /mnt/backup
#
# TODO: Second 2TB SSD not yet detected — add when found.

{
  disko.devices = {
    disk = {
      # ── SSD: OS root + extra scratch (WD Blue SA510 2TB) ────────
      ssd = {
        type = "disk";
        device = "/dev/disk/by-id/ata-WD_Blue_SA510_2.5_2TB_25144ED00458";
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
              size = "500G";
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
                };
              };
            };
            extra = {
              size = "100%";
              content = {
                type = "btrfs";
                extraArgs = [ "-f" ];
                mountpoint = "/mnt/extra";
                mountOptions = [ "compress=zstd" "noatime" ];
              };
            };
          };
        };
      };

      # ── HDD 1 + HDD 2: Backup pool (2×4TB, ~8TB usable) ────────
      #
      # btrfs data=single = JBOD (max space). metadata=raid1 mirrors
      # metadata for resilience. Acceptable for a temporary copy — the
      # originals still live on TrueNAS and critical data is in S3.
      #
      # HDD 2 is referenced in extraArgs — mkfs.btrfs creates the
      # multi-device filesystem in one step.
      hdd-backup = {
        type = "disk";
        device = "/dev/disk/by-id/ata-WDC_WD40EZAZ-00SF3B0_WD-WX52D31D9RDS";
        content = {
          type = "btrfs";
          extraArgs = [
            "-f"
            "-d single"
            "-m raid1"
            "/dev/disk/by-id/ata-WDC_WD40EZAZ-00SF3B0_WD-WX22D21882RT"
          ];
          mountpoint = "/mnt/backup";
          mountOptions = [ "compress=zstd" "noatime" ];
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
