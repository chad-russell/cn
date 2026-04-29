# Arch Laptop Migration Guide

Arch Linux + `systemd-boot` + UKIs + Btrfs snapshots, preserving the current home subvolume.

## Goal

Install Arch in place on this laptop while keeping the current Btrfs data partition and your existing home directory data.

This guide intentionally uses a **hybrid** model:

- **Kernel / boot lane:** deployment-style via `systemd-boot` + UKIs on the EFI partition.
- **Userspace / config lane:** Btrfs subvolumes plus `snapper` / `snap-pac`.

That gives you:

- fast normal Arch package iteration
- native `systemd-boot` + UKI flow
- a clean Btrfs root/home layout
- snapshot-based recovery for userspace/config
- two maintained kernel lanes by installing both `linux` and `linux-lts`

It does **not** try to make Btrfs snapshots directly bootable. With this design, snapshots are for restoring `@`, while kernel boot artifacts live separately on the EFI partition.

## Important Mental Model

This setup deliberately separates two layers:

1. **Boot artifacts**
   - `systemd-boot`
   - UKIs
   - microcode
   - kernel version selection

2. **Root filesystem state**
   - `/`
   - `/etc`
   - `/usr`
   - desktop/session packages
   - most system configuration

That means:

- rolling back a Btrfs snapshot does **not** automatically roll back the UKI
- kernel fallback is handled by choosing a different boot entry
- userspace/config rollback is handled by restoring a Btrfs snapshot of `@`

This is the cleanest Arch version of the model you described.

## Current Disk Layout

Current disk:

- `nvme0n1p1` - 600 MiB FAT EFI system partition
- `nvme0n1p2` - 2 GiB ext4 old Fedora `/boot`
- `nvme0n1p3` - Btrfs data partition containing Fedora Atomic subvolumes

Current Fedora Btrfs subvolumes:

- `root`
- `var`
- `home`

Important: your current `/home -> /var/home` symlink is **not** a problem. The real subvolume on disk is still `home`. In Arch we will mount that preserved subvolume directly at `/home`.

## Target Layout

We will end up with:

- `nvme0n1p1` mounted at `/efi`
  - `systemd-boot`
  - UKIs in `/efi/EFI/Linux/`
- `nvme0n1p2` left unused for now
- `nvme0n1p3` mounted via Btrfs subvolumes:
  - `@` -> `/`
  - `@home` -> `/home`
  - `@snapshots` -> `/.snapshots`

No separate Brioche subvolume for now. Brioche stays inside your home directory.

Start with the smallest subvolume layout that supports the recovery model you want. If you later decide you want `@log`, `@pkg`, `@work`, or other branches for ephemeral-root experiments, add them later instead of front-loading that complexity into day one.

## Swap Choice

This guide uses **zram only** and no disk-backed swap by default.

Why:

- simple
- works well on laptops
- no Btrfs swapfile complexity right now
- no hibernation plumbing to set up during the migration

If you later decide you want true hibernation for maximum overnight battery preservation, add a dedicated `@swap` subvolume later and regenerate the UKIs with `resume=` parameters.

## Before You Reboot Into The ISO

Do these from your current Fedora install first.

### 1. Back up your home directory

Even though we are preserving the Btrfs partition, one wrong command while cleaning up subvolumes can still destroy data.

At minimum, make sure `~/` is backed up to NAS or external storage.

### 2. Copy any system-only secrets you care about

Example for Nebula:

```bash
mkdir -p ~/migration-backups
sudo cp -a /etc/nebula ~/migration-backups/
sudo chown -R "$USER:$USER" ~/migration-backups
```

If you would rather regenerate those later, that is fine too. Backing them up is just faster.

### 3. Keep this repo available somewhere

This guide lives in:

`arch-install-guide.md`

During install you can clone this repo again from the Arch ISO if needed.

## Installation

## 1. Boot The Arch ISO

Boot the Arch ISO in **UEFI mode**.

Confirm:

```bash
ls /sys/firmware/efi/efivars
```

If that directory exists, you are in UEFI mode.

## 2. Bring Up Networking

Set time sync:

```bash
timedatectl set-ntp true
```

For Wi-Fi:

```bash
iwctl
station wlan0 scan
station wlan0 get-networks
station wlan0 connect YOUR_SSID
exit
```

Confirm connectivity:

```bash
ping -c 3 archlinux.org
```

Inspect disks one more time:

```bash
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS,LABEL
```

## 3. Mount The Btrfs Top Level And Rework Subvolumes

Mount the top-level subvolume:

```bash
mount -o subvolid=5 /dev/nvme0n1p3 /mnt
btrfs subvolume list /mnt
```

You should see Fedora's `root`, `var`, and `home` somewhere in that listing.

### Preserve home and create the new layout

Strongly recommended: take a last-chance local read-only snapshot of the preserved home subvolume before renaming anything. This is **not** a substitute for your real backup, but it is cheap insurance against a fat-fingered Btrfs command during the migration.

```bash
btrfs subvolume snapshot -r /mnt/home /mnt/home-pre-arch-install
mv /mnt/home /mnt/@home

btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@snapshots
```

### Delete the old Fedora system subvolumes

Be careful here. Do **not** touch `@home`.

```bash
btrfs subvolume delete -R /mnt/root
btrfs subvolume delete -R /mnt/var
```

If `btrfs subvolume list /mnt` shows other obvious old ostree deployment subvolumes, delete those too, but only after verifying they belong to the old Fedora system and not your preserved home data.

Unmount the top level:

```bash
umount /mnt
```

## 4. Mount The New Target Layout

Mount the new root:

```bash
mount -o subvol=/@,compress=zstd:1,noatime /dev/nvme0n1p3 /mnt
```

Create mount points:

```bash
mkdir -p /mnt/{home,efi}
```

Mount the other Btrfs subvolumes:

```bash
mount -o subvol=/@home,compress=zstd:1,noatime /dev/nvme0n1p3 /mnt/home
```

Do **not** mount `@snapshots` yet. Snapper setup is cleaner if we add that after `create-config`.

Reformat the EFI partition and mount it at `/efi`:

```bash
mkfs.fat -F 32 /dev/nvme0n1p1
mount /dev/nvme0n1p1 /mnt/efi
```

We intentionally leave `nvme0n1p2` alone for now.

## 5. Install The Base System

Install the minimal system plus the packages this design depends on:

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

Why both kernels?

- `linux` is your normal bleeding-edge Arch kernel
- `linux-lts` is the cleanest maintained fallback lane on Arch

That is the simplest stock Arch approximation of the A/B kernel idea you want.

## 6. Generate fstab And Chroot

Generate the initial `fstab`:

```bash
genfstab -U /mnt >> /mnt/etc/fstab
```

Chroot with systemd mode so `bootctl` can work properly with EFI variables:

```bash
arch-chroot -S /mnt
```

## 7. Base System Configuration

### Timezone

```bash
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
hwclock --systohc
```

### Locale

Edit:

```bash
nvim /etc/locale.gen
```

Uncomment:

```text
en_US.UTF-8 UTF-8
```

Then run:

```bash
locale-gen
printf 'LANG=en_US.UTF-8\n' > /etc/locale.conf
```

### Hostname and hosts

```bash
printf 'think\n' > /etc/hostname
cat >/etc/hosts <<'EOF'
127.0.0.1 localhost
::1       localhost
127.0.1.1 think.localdomain think
EOF
```

### Enable networking

```bash
systemctl enable NetworkManager
```

## 8. Configure systemd-boot And UKIs

This guide uses the simplest stock Arch UKI flow:

- `mkinitcpio` generates the UKIs
- `systemd-boot` auto-detects them from `/efi/EFI/Linux/`

No custom kernel hooks, no GRUB, no extra boot menu generator.

### 8.1 Create the kernel command line

Get the Btrfs filesystem UUID:

```bash
ROOT_UUID=$(blkid -s UUID -o value /dev/nvme0n1p3)
mkdir -p /etc/kernel
```

Write the embedded UKI kernel command line:

```bash
printf 'root=UUID=%s rw rootflags=subvol=/@ quiet\n' "$ROOT_UUID" >/etc/kernel/cmdline
```

`rootflags=subvol=/@` is the important part. We use a subvolume path, not a subvolume ID, so restoring snapshots later does not force you to chase changing IDs.

### 8.2 Install systemd-boot

```bash
bootctl --esp-path=/efi install
systemctl enable systemd-boot-update.service
```

### 8.3 Write loader configuration

Create `/efi/loader/loader.conf`:

```bash
cat >/efi/loader/loader.conf <<'EOF'
default arch-linux.efi
timeout 4
console-mode max
editor no
EOF
```

### 8.4 Configure mkinitcpio to emit UKIs

Create the directory where systemd-boot will auto-detect UKIs:

```bash
mkdir -p /efi/EFI/Linux
```

Before generating UKIs, quickly verify that `/etc/mkinitcpio.conf` still includes the `microcode` hook. On current Arch defaults it should, but this is worth checking because installing `intel-ucode` alone is not enough if the hook is missing.

```bash
grep '^HOOKS=' /etc/mkinitcpio.conf
```

Edit the mainline preset:

```bash
nvim /etc/mkinitcpio.d/linux.preset
```

Make it look like this:

```text
ALL_kver="/boot/vmlinuz-linux"

PRESETS=('default')

#default_image="/boot/initramfs-linux.img"
default_uki="/efi/EFI/Linux/arch-linux.efi"
default_options="--splash=/usr/share/systemd/bootctl/splash-arch.bmp"
```

Then edit the LTS preset:

```bash
nvim /etc/mkinitcpio.d/linux-lts.preset
```

Make it look like this:

```text
ALL_kver="/boot/vmlinuz-linux-lts"

PRESETS=('default')

#default_image="/boot/initramfs-linux-lts.img"
default_uki="/efi/EFI/Linux/arch-linux-lts.efi"
default_options="--splash=/usr/share/systemd/bootctl/splash-arch.bmp"
```

### 8.5 Build the UKIs

```bash
mkinitcpio -P
bootctl list
```

At this point you should see systemd-boot recognizing your two UKIs.

This keeps the boot menu intentionally small:

- `linux` as the normal fast-moving lane
- `linux-lts` as the conservative fallback lane

After installation, future kernel and microcode updates should continue to rebuild the UKIs automatically through Arch's normal `mkinitcpio` packaging hooks.

## 9. Configure Snapper With The Suggested Btrfs Layout

We want snapshots stored in `@snapshots`, not inside `@` itself.

### 9.1 Create the Snapper config

```bash
snapper -c root create-config /
```

That creates a `/.snapshots` subvolume inside `@`. We do not want that final layout, so replace it with the separate `@snapshots` mount.

### 9.2 Replace the generated `.snapshots` subvolume

```bash
btrfs subvolume delete /.snapshots
mkdir /.snapshots
```

Append the `@snapshots` mount to `/etc/fstab`:

```bash
printf 'UUID=%s /.snapshots btrfs subvol=/@snapshots,compress=zstd:1,noatime 0 0\n' "$ROOT_UUID" >> /etc/fstab
```

Mount it:

```bash
mount /.snapshots
chmod 750 /.snapshots
```

### 9.3 Enable automatic snapshots

```bash
systemctl enable snapper-timeline.timer
systemctl enable snapper-cleanup.timer
```

`snap-pac` will automatically create pre/post snapshots around pacman transactions.

### 9.4 Optional: tune snapshot retention now

If you want a more conservative retention policy on a laptop, edit:

```bash
nvim /etc/snapper/configs/root
```

Reasonable starting point:

```text
TIMELINE_LIMIT_HOURLY="6"
TIMELINE_LIMIT_DAILY="7"
TIMELINE_LIMIT_WEEKLY="4"
TIMELINE_LIMIT_MONTHLY="0"
TIMELINE_LIMIT_YEARLY="0"
```

You can tune this later.

## 10. Configure zram

Create `/etc/systemd/zram-generator.conf`:

```bash
cat >/etc/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
EOF
```

Nothing else is required right now. The generator will create the swap device at boot.

After the first boot, verify with:

```bash
swapon --show
```

## 11. Create Your User

Your preserved home data should end up at `/home/crussell`.

Create the matching user with UID `1000` without creating a fresh home directory over the preserved one:

```bash
useradd -M -u 1000 -d /home/crussell -G wheel -s /bin/bash crussell
id crussell
ls -ldn /home/crussell
passwd crussell
passwd root
```

If `/home/crussell` is not already owned by `1000:1000`, fix the directory ownership explicitly:

```bash
chown crussell:crussell /home/crussell
```

Only do a recursive `chown -R` after inspecting the tree and deciding you actually need it.

Enable `sudo` for wheel:

```bash
EDITOR=nvim visudo
```

Uncomment:

```text
%wheel ALL=(ALL:ALL) ALL
```

## 12. Final Checks Before Reboot

Run these:

```bash
bootctl list
findmnt / /home /efi /.snapshots
ls /efi/EFI/Linux
cat /etc/fstab
```

Things to confirm:

- `/` is on `subvol=/@`
- `/home` is on `subvol=/@home`
- `/.snapshots` is on `subvol=/@snapshots`
- `/efi` is mounted
- UKIs exist in `/efi/EFI/Linux/`

## 13. Reboot

Exit and unmount:

```bash
exit
umount -R /mnt
reboot
```

## First Boot Checklist

After booting the installed system:

### 1. Verify the mount layout

```bash
findmnt / /home /.snapshots /efi
```

### 2. Verify snapper works

```bash
sudo snapper -c root list
```

### 3. Verify zram

```bash
swapon --show
```

### 4. Verify boot entries

```bash
bootctl list
```

You should see at least:

- `arch-linux.efi`
- `arch-linux-lts.efi`

### 5. Audit for stale `/var/home` references

You are intentionally moving back to a normal Arch `/home` layout. If any old scripts, desktop files, or config snippets still hardcode Fedora's `/var/home`, find them now:

```bash
rg -n '/var/home' ~/.config ~/.local ~/Code /etc 2>/dev/null
```

### 6. Restore any saved system-only files

For example, Nebula:

```bash
sudo mkdir -p /etc/nebula
sudo cp -a ~/migration-backups/nebula/. /etc/nebula/
```

### 7. Re-apply your declarative user environment

At this point you can reinstall Brioche / Brunch and re-apply your config.

## How Rollback Works In This Design

## Kernel / boot rollback

Use the systemd-boot menu:

- normal path: `arch-linux.efi`
- safety path: `arch-linux-lts.efi`

This is your clean deployment-style boot lane.

## Userspace / config rollback

Use Snapper/Btrfs to restore `@`.

With this design, the clean recovery workflow is:

1. boot the Arch ISO
2. mount the Btrfs top-level subvolume
3. rename the broken `@`
4. make a writable snapshot from `@snapshots/N/snapshot` back to `@`
5. reboot

That restores userspace/config while leaving the boot lane alone.

If the restored userspace is far out of sync with the current kernel lane, just boot normally and run a fresh `pacman -Syu` to re-converge.

## Restoring `@` From A Snapshot

From the Arch ISO:

```bash
mount -o subvolid=5 /dev/nvme0n1p3 /mnt
```

Find the snapshot number:

```bash
ls /mnt/@snapshots
```

Move the broken root out of the way:

```bash
mv /mnt/@ /mnt/@.broken
```

Restore a writable root from a Snapper snapshot:

```bash
btrfs subvolume snapshot /mnt/@snapshots/SNAPSHOT_NUMBER/snapshot /mnt/@
```

Unmount and reboot.

If you are happy with the restored system later, delete `@.broken`.

## Adding `@work` / `@personal` Later

This setup can grow into multi-root Btrfs branches later, but because you chose **UKIs with embedded cmdlines**, there is one extra detail:

- each bootable root branch needs its own UKI cmdline with the matching `rootflags=subvol=/...`

That means the future pattern is:

1. create a new root branch:

```bash
mount -o subvolid=5 /dev/nvme0n1p3 /mnt
btrfs subvolume snapshot /mnt/@ /mnt/@work
umount /mnt
```

2. build a second UKI whose embedded cmdline points at `subvol=/@work`

You can do that later by either:

- maintaining additional preset files / UKI names, or
- switching to loader entries with UKIs built using `--no-cmdline`

For now, staying with one root `@` keeps the install straightforward.

## Adding “Erase Your Darlings” Later

This layout is already prepared for it.

Because `@home` and `@snapshots` are already separate, you can later make root ephemeral without touching your actual data. If you eventually decide you want logs or the pacman cache outside that ephemeral root, split them out at that point rather than now.

The rough future shape would be:

1. settle on a clean baseline
2. snapshot `@` to something like `@base`
3. on boot, replace `@` with a fresh writable snapshot of `@base`

That can be done later with either:

- an initramfs hook
- or a very early boot service

I would **not** start there. Get the plain system stable first, then add ephemeral root once you have lived with the subvolume layout for a while.

## Notes And Caveats

- `nvme0n1p2` is intentionally untouched in this version. The likely future uses are XBOOTLDR, hibernation/swap, or a rescue partition, but none of those are worth repartitioning risk during this migration.
- The pacman database stays on `@`. That is intentional. Do not move `/var/lib/pacman` out to its own subvolume if you want normal Arch package behavior.
- The pacman package cache also stays on `@` for now. If you later want smaller root snapshots or more aggressive ephemeral-root experiments, split it out then instead of now.
- `snap-pac` snapshots are great for recovery, but this is still Arch, not rpm-ostree or NixOS generations. Think of snapshots as safety rails, not as perfect transactional history.
- If you eventually want true disk-backed hibernation, add a dedicated swap subvolume later instead of trying to cram it into this migration.

## Short Version Of The Design

If you want to remember this setup in one sentence:

**Boot with `systemd-boot` and UKIs, keep two kernel families (`linux` + `linux-lts`), and use Btrfs snapshots to protect the mutable Arch userspace without over-structuring the filesystem on day one.**