{
  # k3 was installed with a host-specific disk layout:
  #   - /dev/nvme0n1: 512M EFI + 8G swap + ext4 root
  #   - /dev/sda: left unmanaged by disko; mounted explicitly by UUID
  #     from hosts/k3/configuration.nix as /mnt/data.
  #
  # Do not use modules/elitedesk-disk-config.nix here because that module
  # also declares /mnt/data by partlabel and conflicts with k3's live UUID
  # mount.

  disko.devices = {
    disk = {
      main = {
        device = "/dev/nvme0n1";
        type = "disk";
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
    };
  };
}
