# ── NFS mount helper ────────────────────────────────────────────────
#
# Shared fileSystems entry for NAS NFS mounts (soft, systemd-automounted).
# The options list is fleet policy (same seven options on every NFS mount
# from hosts/{bee,bees}); this keeps it defined once so the hosts cannot
# drift apart mount by mount.
#
# Usage:
#
#   imports = [
#     (import ../../lib/nfs-mount.nix {
#       device = "192.168.20.31:/pool/media";
#       mountPoint = "/mnt/media";
#     })
#   ];

{ device, mountPoint }:

{
  fileSystems.${mountPoint} = {
    inherit device;
    fsType = "nfs";
    options = [
      "x-systemd.automount"
      "noauto"
      "timeo=14"
      "nfsvers=4"
      "rw"
      "soft"
      "intr"
    ];
  };
}
