# Arch Live Install Checklist

Short version of `arch-install-guide.md` for use from the Arch ISO.

## Before touching disks

- Confirm you have a real backup of `~/`
- If needed, copy system-only secrets first, e.g. `/etc/nebula`
- Target disk layout:
  - `nvme0n1p1` = EFI, will be reformatted FAT32 and mounted at `/efi`
  - `nvme0n1p2` = leave alone
  - `nvme0n1p3` = existing Btrfs data partition, preserved

## 1. Boot and network

```bash
ls /sys/firmware/efi/efivars
timedatectl set-ntp true
```

If on Wi-Fi:

```bash
iwctl
station wlan0 scan
station wlan0 get-networks
station wlan0 connect YOUR_SSID
exit
```

Test:

```bash
ping -c 3 archlinux.org
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS,LABEL
```

## 2. Rework Btrfs subvolumes

Mount top level:

```bash
mount -o subvolid=5 /dev/nvme0n1p3 /mnt
btrfs subvolume list /mnt
```

Create the new layout and preserve home:

```bash
btrfs subvolume snapshot -r /mnt/home /mnt/home-pre-arch-install
mv /mnt/home /mnt/@home
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@snapshots
```

Delete old Fedora system subvolumes only:

```bash
btrfs subvolume delete -R /mnt/root
btrfs subvolume delete -R /mnt/var
```

Do **not** touch `@home`.

Unmount:

```bash
umount /mnt
```

## 3. Mount the target layout

```bash
mount -o subvol=/@,compress=zstd:1,noatime /dev/nvme0n1p3 /mnt
mkdir -p /mnt/{home,efi}
mount -o subvol=/@home,compress=zstd:1,noatime /dev/nvme0n1p3 /mnt/home
mkfs.fat -F 32 /dev/nvme0n1p1
mount /dev/nvme0n1p1 /mnt/efi
```

Do not mount `@snapshots` yet.

## 4. Install Arch

```bash
pacstrap -K /mnt \
  base base-devel \
  linux linux-lts \
  linux-firmware intel-ucode \
  btrfs-progs \
  networkmanager \
  sudo git neovim \
  snapper snap-pac \
  zram-generator
```

## 5. fstab and chroot

```bash
genfstab -U /mnt >> /mnt/etc/fstab
arch-chroot -S /mnt
```

## 6. Base config

Timezone:

```bash
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
hwclock --systohc
```

Locale:

```bash
nvim /etc/locale.gen
locale-gen
printf 'LANG=en_US.UTF-8\n' > /etc/locale.conf
```

Uncomment:

```text
en_US.UTF-8 UTF-8
```

Hostname:

```bash
printf 'think\n' > /etc/hostname
cat >/etc/hosts <<'EOF'
127.0.0.1 localhost
::1       localhost
127.0.1.1 think.localdomain think
EOF
systemctl enable NetworkManager
```

## 7. systemd-boot + UKIs

Get root UUID and create cmdline:

```bash
ROOT_UUID=$(blkid -s UUID -o value /dev/nvme0n1p3)
mkdir -p /etc/kernel
printf 'root=UUID=%s rw rootflags=subvol=/@ quiet\n' "$ROOT_UUID" >/etc/kernel/cmdline
```

Install bootloader:

```bash
bootctl --esp-path=/efi install
systemctl enable systemd-boot-update.service
mkdir -p /efi/EFI/Linux
cat >/efi/loader/loader.conf <<'EOF'
default arch-linux.efi
timeout 4
console-mode max
editor no
EOF
```

Verify `/etc/mkinitcpio.conf` still includes the `microcode` hook:

```bash
grep '^HOOKS=' /etc/mkinitcpio.conf
```

Edit `/etc/mkinitcpio.d/linux.preset` to:

```text
ALL_kver="/boot/vmlinuz-linux"

PRESETS=('default')

#default_image="/boot/initramfs-linux.img"
default_uki="/efi/EFI/Linux/arch-linux.efi"
default_options="--splash=/usr/share/systemd/bootctl/splash-arch.bmp"
```

Edit `/etc/mkinitcpio.d/linux-lts.preset` to:

```text
ALL_kver="/boot/vmlinuz-linux-lts"

PRESETS=('default')

#default_image="/boot/initramfs-linux-lts.img"
default_uki="/efi/EFI/Linux/arch-linux-lts.efi"
default_options="--splash=/usr/share/systemd/bootctl/splash-arch.bmp"
```

Build UKIs:

```bash
mkinitcpio -P
bootctl list
```

## 8. Snapper layout

Create config:

```bash
snapper -c root create-config /
```

Replace generated `/.snapshots` subvolume with mounted `@snapshots`:

```bash
btrfs subvolume delete /.snapshots
mkdir /.snapshots
printf 'UUID=%s /.snapshots btrfs subvol=/@snapshots,compress=zstd:1,noatime 0 0\n' "$ROOT_UUID" >> /etc/fstab
mount /.snapshots
chmod 750 /.snapshots
systemctl enable snapper-timeline.timer
systemctl enable snapper-cleanup.timer
```

Optional retention tuning:

```bash
nvim /etc/snapper/configs/root
```

Suggested:

```text
TIMELINE_LIMIT_HOURLY="6"
TIMELINE_LIMIT_DAILY="7"
TIMELINE_LIMIT_WEEKLY="4"
TIMELINE_LIMIT_MONTHLY="0"
TIMELINE_LIMIT_YEARLY="0"
```

## 9. zram

```bash
cat >/etc/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
EOF
```

## 10. User account

```bash
useradd -M -u 1000 -d /home/crussell -G wheel -s /bin/bash crussell
id crussell
ls -ldn /home/crussell
# Only if ownership is not already 1000:1000:
chown crussell:crussell /home/crussell
passwd crussell
passwd root
EDITOR=nvim visudo
```

Uncomment:

```text
%wheel ALL=(ALL:ALL) ALL
```

## 11. Final checks

```bash
bootctl list
findmnt / /home /efi /.snapshots
ls /efi/EFI/Linux
cat /etc/fstab
```

Confirm:

- `/` on `subvol=/@`
- `/home` on `subvol=/@home`
- `/.snapshots` on `subvol=/@snapshots`
- `/efi` mounted
- UKIs exist

## 12. Reboot

```bash
exit
umount -R /mnt
reboot
```

## First boot quick checks

```bash
findmnt / /home /.snapshots /efi
bootctl list
sudo snapper -c root list
swapon --show
```

Expected boot entries:

- `arch-linux.efi`
- `arch-linux-lts.efi`
