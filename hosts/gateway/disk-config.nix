# ── Gateway Disk Layout ────────────────────────────────────────────
#
# Hetzner Cloud x86_64 VPS — single /dev/sda, legacy BIOS boot.
# GPT with BIOS boot partition (EF02) for GRUB + ext4 root.

{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/sda";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1M";
              type = "EF02"; # BIOS boot partition for GRUB
              priority = 1;
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
    };
  };
}
