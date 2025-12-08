{ ... }: {
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/nvme0n1";
        content = {
          type = "gpt";
          partitions = {
            # EFI System Partition - 4G for multiple NixOS generations
            esp = {
              size = "4G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            # Main BTRFS partition with optimized options for laptop SSD
            root = {
              size = "100%";
              content = {
                type = "btrfs";
                extraArgs = [ "-f" ]; # Force overwrite if needed
                subvolumes = {
                  # Root subvolume
                  "@" = {
                    mountpoint = "/";
                    mountOptions = [ 
                      "compress=zstd"
                      "noatime"
                      "ssd"
                      "space_cache=v2"
                      "discard=async"
                    ];
                  };
                  # Home subvolume - separate for easy snapshots/backups
                  "@home" = {
                    mountpoint = "/home";
                    mountOptions = [ 
                      "compress=zstd"
                      "noatime"
                      "ssd"
                      "space_cache=v2"
                      "discard=async"
                    ];
                  };
                  # Nix store - separate subvolume for potential different snapshot policies
                  "@nix" = {
                    mountpoint = "/nix";
                    mountOptions = [ 
                      "compress=zstd"
                      "noatime"
                      "ssd"
                      "space_cache=v2"
                      "discard=async"
                    ];
                  };
                  # Var - state, but exclude logs and cache
                  "@var" = {
                    mountpoint = "/var";
                    mountOptions = [ 
                      "compress=zstd"
                      "noatime"
                      "ssd"
                      "space_cache=v2"
                      "discard=async"
                    ];
                  };
                  # Separate var/log - excluded from snapshots, different retention
                  "@var-log" = {
                    mountpoint = "/var/log";
                    mountOptions = [ 
                      "compress=zstd"
                      "noatime"
                      "ssd"
                      "space_cache=v2"
                      "discard=async"
                    ];
                  };
                  # Separate var/cache - excluded from snapshots
                  "@var-cache" = {
                    mountpoint = "/var/cache";
                    mountOptions = [ 
                      "compress=zstd"
                      "noatime"
                      "ssd"
                      "space_cache=v2"
                      "discard=async"
                    ];
                  };
                  # Snapshots directory
                  "@snapshots" = {
                    mountpoint = "/.snapshots";
                    mountOptions = [ 
                      "compress=zstd"
                      "noatime"
                      "ssd"
                      "space_cache=v2"
                      "discard=async"
                    ];
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

