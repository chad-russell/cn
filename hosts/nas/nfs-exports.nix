# ── nas: NFS Exports ───────────────────────────────────────────────
#
# NFSv4 exports for bees and bee consumers.
# The new export paths use /pool/* (btrfs subvolumes) instead of
# the old TrueNAS /mnt/tank/* paths.

{ config, lib, ... }:

{
  services.nfs.server = {
    enable = true;
    exports = ''
      /pool/media    192.168.20.0/24(rw,no_subtree_check,no_root_squash,fsid=1)
      /pool/photos   192.168.20.0/24(rw,no_subtree_check,no_root_squash,fsid=2)
      /pool/backups  192.168.20.0/24(rw,no_subtree_check,no_root_squash,fsid=3)
      /pool/surveillance 192.168.20.0/24(rw,no_subtree_check,no_root_squash,fsid=4)
    '';
  };

  # Open NFS ports in firewall
  networking.firewall.allowedTCPPorts = [ 2049 ];
}
