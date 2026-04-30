#!/usr/bin/env bash
# =============================================================================
# NixOS Partitioning & Formatting — ThinkPad T14
# 
# Run this AFTER kexec-booting into the NixOS installer.
# 
# Disk: /dev/nvme0n1 (477GB NVMe)
# Layout:
#   p1: ESP       2 GB     FAT32      /boot
#   p2: swap      40 GB    linux-swap
#   p3: root      ~435 GB  Btrfs      (subvolumes: @, @home, @nix, @var-log)
# 
# WARNING: DESTROYS ALL DATA ON /dev/nvme0n1
# =============================================================================

set -euo pipefail

DISK="/dev/nvme0n1"
LABEL_ROOT="nixos"
LABEL_BOOT="boot"
LABEL_SWAP="swap"

# ---------------------------------------------------------------------------
# 1. Wipe and partition
# ---------------------------------------------------------------------------
echo ">>> Creating GPT partition table on ${DISK}..."
parted "${DISK}" --script mklabel gpt

echo ">>> Creating ESP (2 GB)..."
parted "${DISK}" --script mkpart ESP fat32 1MiB 2GiB
parted "${DISK}" --script set 1 esp on

echo ">>> Creating swap (40 GB)..."
parted "${DISK}" --script mkpart swap linux-swap 2GiB 42GiB

echo ">>> Creating root (rest of disk)..."
parted "${DISK}" --script mkpart root btrfs 42GiB 100%

echo ""
echo ">>> Partition table:"
parted "${DISK}" --script print
echo ""

# ---------------------------------------------------------------------------
# 2. Format
# ---------------------------------------------------------------------------
echo ">>> Formatting ESP..."
mkfs.fat -F 32 -n "${LABEL_BOOT}" "${DISK}p1"

echo ">>> Formatting swap..."
mkswap -L "${LABEL_SWAP}" "${DISK}p2"

echo ">>> Formatting root as Btrfs..."
mkfs.btrfs -L "${LABEL_ROOT}" "${DISK}p3"

echo ""

# ---------------------------------------------------------------------------
# 3. Create Btrfs subvolumes
# ---------------------------------------------------------------------------
echo ">>> Mounting Btrfs to create subvolumes..."
mount -o compress=zstd:3 "${DISK}p3" /mnt

echo ">>> Creating subvolumes..."
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@nix
btrfs subvolume create /mnt/@var-log

echo ">>> Unmounting..."
umount /mnt

echo ""

# ---------------------------------------------------------------------------
# 4. Mount everything
# ---------------------------------------------------------------------------
echo ">>> Mounting subvolumes..."

# Root
mount -o subvol=@,compress=zstd:3,noatime,ssd,discard=async "${DISK}p3" /mnt

# Home
mkdir -p /mnt/home
mount -o subvol=@home,compress=zstd:3,noatime,ssd,discard=async "${DISK}p3" /mnt/home

# Nix store
mkdir -p /mnt/nix
mount -o subvol=@nix,compress=zstd:3,noatime,ssd,discard=async "${DISK}p3" /mnt/nix

# Var log
mkdir -p /mnt/var/log
mount -o subvol=@var-log,compress=zstd:3,noatime,ssd "${DISK}p3" /mnt/var/log

# Boot
mkdir -p /mnt/boot
mount -o umask=077 "${DISK}p1" /mnt/boot

# Swap
swapon "${DISK}p2"

echo ""

# ---------------------------------------------------------------------------
# 5. Verify
# ---------------------------------------------------------------------------
echo ">>> Final mount layout:"
df -hT /mnt /mnt/home /mnt/nix /mnt/var/log /mnt/boot
echo ""
echo ">>> Swap:"
swapon --show
echo ""

echo "============================================"
echo " Partitioning complete!"
echo ""
echo " Next steps:"
echo "   nixos-generate-config --root /mnt"
echo "   nano /mnt/etc/nixos/configuration.nix"
echo "   nixos-install"
echo "   reboot"
echo "============================================"
